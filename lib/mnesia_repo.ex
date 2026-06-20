defmodule MishkaInstaller.MnesiaRepo do
  @moduledoc """
  Boots, supervises and **dynamically clusters** the [Mnesia](https://www.erlang.org/doc/man/mnesia)
  store used by `MishkaInstaller`.

  On start it (re)configures the Mnesia directory, creates the schema, starts Mnesia, waits for the
  local tables, creates the essential tables, and broadcasts `:synchronized` on the `"mnesia"`
  PubSub channel so the event and installer layers can come online.

  It also watches the BEAM cluster (`:net_kernel.monitor_nodes/1`) and keeps Mnesia membership in
  sync at runtime: a configured peer that connects *after* boot is joined automatically.

  ## Configuration

  Configure under the `:mishka_installer` application env, keyed by this module:

  ```elixir
  config :mishka_installer, MishkaInstaller.MnesiaRepo,
    mnesia_dir: "/var/lib/my_app/mnesia",
    essential: [MishkaInstaller.Event.Event, MishkaInstaller.Installer.Installer],
    cluster_nodes: :auto,
    dynamic_membership: true,
    wait_timeout: 60_000,
    wait_retries: 5
  ```

  - `:mnesia_dir` — where Mnesia stores its files. Defaults to `".mnesia/<env>"` under the project.
  - `:essential` — modules whose `database_config/0` defines a table to create on boot. Defaults to
    `[MishkaInstaller.Installer.Installer, MishkaInstaller.Event.Event]`.
  - `:cluster_nodes` — the seed/existing cluster nodes this node should **join**. `:auto` (default)
    and `[]` mean **standalone seed** (this node owns the schema). A non-empty list makes this node a
    **joiner**: it wipes its local schema, connects to those nodes, becomes a `disc_copies` member and
    copies each essential table. Run **one** seed node (`:auto`/`[]`) and point the others at it
    (`cluster_nodes: [seed]`). A joiner whose seed is not reachable yet does **not** crash — it boots
    `:pending` (empty, no tables) and joins as soon as a configured node connects. Forming the BEAM
    cluster (`libcluster`/`Node.connect`) is a separate, prior step.
  - `:dynamic_membership` — watch `:net_kernel.monitor_nodes/1` and join configured peers that
    connect after boot. Defaults to `true`, but it is **only active when `:cluster_nodes` lists
    peers** — a standalone/default node (`:auto`/`[]`) never watches the cluster and stays fully
    passive regardless of this flag. Set `false` to opt a clustered node out of runtime monitoring
    (boot-time join only).

  > #### Cluster limits {: .warning}
  >
  > Mnesia has **no automatic split-brain resolution**. On a network partition both sides keep
  > writing; on heal an `inconsistent_database` event is emitted (alarmed via telemetry + a critical
  > log) and an **operator** must resolve it. A node going **down** is never auto-evicted (a transient
  > netsplit would otherwise destroy a healthy replica) — removing a node is an explicit operator
  > action. Recovery helpers (`force_load_table`/`set_master_nodes`) are not yet implemented.
  - `:wait_timeout` / `:wait_retries` — one wait "slice" (ms) and how many slices to wait while
    `disc_copies` tables load from disk into RAM before giving up. Raise these for large datasets.

  > #### Restart {: .info}
  >
  > On a restart where Mnesia is already running on the configured dir with the essential tables
  > loaded, boot is a no-op re-announce — it does **not** stop/re-init Mnesia under the running
  > event/installer processes.

  ## Telemetry

  All events use the `[:mishka_installer, :mnesia, ...]` prefix:

  - `[:mishka_installer, :mnesia, :init, :start | :stop | :exception]` — a `:telemetry.span/3`
    around boot. `:stop` carries `:duration`; metadata: `:node`, `:result`, `:tables`.
  - `[:mishka_installer, :mnesia, :table]` — once per essential table. Metadata: `:table`,
    `:status` (`:created` | `:already_exists` | `:already_loaded` | `:copied` | `:error`).
  - `[:mishka_installer, :mnesia, :synchronized]` — after the boot broadcast. Metadata: `:node`,
    `:tables`.
  - `[:mishka_installer, :mnesia, :health_check]` — periodic. Measurements: `:table_count`,
    `:schema_count`. Metadata: `:node`, `:healthy?`, `:missing`.
  - `[:mishka_installer, :mnesia, :inconsistent_database]` — split-brain detected. Metadata:
    `:node`, `:context`.
  - `[:mishka_installer, :mnesia, :cluster, :nodeup]` — a node connected. Metadata: `:node`, `:peer`,
    `:action` (`:joined` | `:connected` | `:already_member` | `:ignored` | `:pending` | `{:error, term}`).
  - `[:mishka_installer, :mnesia, :cluster, :nodedown]` — a node disconnected (log + alarm only, no
    eviction). Metadata: `:node`, `:peer`, `:db_member?`.
  """
  use GenServer
  require Logger
  alias MishkaInstaller.Event.Event
  alias MishkaInstaller.Installer.Installer
  alias MishkaInstaller.Helper.MnesiaAssistant
  alias MishkaInstaller.Helper.MnesiaAssistant.{Schema, Table}
  alias MishkaInstaller.Helper.MnesiaAssistant.Error, as: MError

  # I got the basic idea from https://github.com/processone/ejabberd
  @identifier :mishka_mnesia_repo
  @telemetry [:mishka_installer, :mnesia]
  @health_interval 10_000
  @wait_timeout 60_000
  @wait_retries 5

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            tables: [atom()],
            schemas: list(),
            essential: [module()],
            status: :pending | :synchronized | :inconsistent,
            dynamic: boolean()
          }
    defstruct tables: [], schemas: [], essential: [], status: :pending, dynamic: true
  end

  ################################################################################
  ######################## (▰˘◡˘▰) Public API (▰˘◡˘▰) #######################
  ################################################################################
  @doc "Starts the Mnesia repository process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @doc "Returns the current repository state."
  @spec state() :: struct()
  def state(), do: GenServer.call(__MODULE__, :state)

  @doc """
  Returns each local table (except `:schema`) with its storage type and `local_content` flag.
  """
  @spec schemas() :: [{atom(), keyword()}]
  def schemas() do
    Enum.flat_map(:mnesia.system_info(:tables), fn
      :schema ->
        []

      tab ->
        [
          {tab,
           [
             storage_type: :mnesia.table_info(tab, :storage_type),
             local_content: :mnesia.table_info(tab, :local_content)
           ]}
        ]
    end)
  end

  ################################################################################
  ######################## (▰˘◡˘▰) Callbacks (▰˘◡˘▰) ########################
  ################################################################################
  @impl true
  def init(_state) do
    Logger.metadata(domain: [:mishka_installer, :mnesia])

    :telemetry.span(@telemetry ++ [:init], %{node: node()}, fn ->
      result = bootstrap()
      {result, %{node: node(), result: elem(result, 0), tables: local_tables()}}
    end)
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state, state}

  def handle_call(request, from, state) do
    Logger.warning(
      "[mishka_installer.mnesia] unexpected call from #{inspect(from)}: #{inspect(request)}"
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("[mishka_installer.mnesia] unexpected cast: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    schedule_health_check()

    tables = local_tables()
    missing = Enum.reject(state.essential, &(&1 in tables))
    healthy? = missing == []

    if !healthy?,
      do:
        Logger.warning(
          "[mishka_installer.mnesia] health check found missing tables: #{inspect(missing)}"
        )

    :telemetry.execute(
      @telemetry ++ [:health_check],
      %{table_count: length(tables), schema_count: length(schemas())},
      %{node: node(), healthy?: healthy?, missing: missing}
    )

    {:noreply, state}
  end

  # A configured peer joined the BEAM cluster — reconcile Mnesia membership.
  def handle_info({:nodeup, peer}, %State{dynamic: true} = state) do
    {:noreply, on_nodeup(peer, state)}
  end

  def handle_info({:nodeup, _peer}, state), do: {:noreply, state}

  # A node left the BEAM cluster. We log + alarm only and NEVER auto-evict: Mnesia keeps a downed
  # node as a known `db_node` and it re-joins on restart; dropping its schema copy on a transient
  # partition would destroy a healthy replica. Eviction is an explicit operator action.
  def handle_info({:nodedown, peer}, %State{dynamic: true} = state) do
    db_member? = peer in db_nodes()

    Logger.warning(
      "[mishka_installer.mnesia] node down: #{inspect(peer)} (db_member?=#{db_member?}); " <>
        "not auto-evicting — operator action required to remove it"
    )

    cluster_event(:nodedown, peer, %{db_member?: db_member?})
    {:noreply, state}
  end

  def handle_info({:nodedown, _peer}, state), do: {:noreply, state}

  def handle_info({:mnesia_system_event, {:inconsistent_database, context, node}}, state) do
    Logger.critical(
      "[mishka_installer.mnesia] split-brain: #{inspect(context)} with #{inspect(node)} — operator action required"
    )

    :telemetry.execute(
      @telemetry ++ [:inconsistent_database],
      %{system_time: System.system_time()},
      %{node: node, context: context}
    )

    {:noreply, %{state | status: :inconsistent}}
  end

  def handle_info({:mnesia_system_event, _event}, state), do: {:noreply, state}

  def handle_info(info, state) do
    Logger.warning("[mishka_installer.mnesia] unexpected info: #{inspect(info)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  @impl true
  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  ################################################################################
  ######################## (▰˘◡˘▰) Boot (▰˘◡˘▰) #############################
  ################################################################################
  defp bootstrap() do
    config = config()
    # Dynamic membership is only meaningful with configured peers: a standalone/default node
    # (`:auto`/`[]`) never watches the BEAM cluster — it stays fully passive.
    dynamic = config[:dynamic_membership] and peers(config[:cluster_nodes]) != []
    monitor_nodes(dynamic)

    if already_running?(config) do
      Logger.debug(
        "[mishka_installer.mnesia] already running on #{inspect(node())}; re-announcing"
      )

      ready(config, dynamic)
    else
      full_boot(config, dynamic)
    end
  end

  defp full_boot(config, dynamic) do
    configure_dir(config[:mnesia_dir])
    boot(peers(config[:cluster_nodes]), config, dynamic)
  end

  # Standalone / seed node: own the disc schema and create the essential tables. `:auto` and `[]`
  # take this path.
  defp boot([], config, dynamic) do
    if node() in db_nodes() do
      maybe_create_schema()
      start_and_subscribe()

      with :ok <- wait_for(local_tables(), config),
           :ok <- create_essential_tables(config[:essential]),
           :ok <- wait_for(config[:essential], config) do
        ready(config, dynamic)
      end
    else
      Logger.critical(
        "[mishka_installer.mnesia] node mismatch: #{inspect(node())} owns a different schema dir"
      )

      {:stop, :node_name_mismatch}
    end
  end

  # Joining node: wipe any local schema so we join from an empty one (the documented prerequisite),
  # then try the join. If no configured node is reachable yet we stay `:pending` (still empty, so no
  # split-brain risk) and finish the join when one connects (see `on_nodeup/2`).
  defp boot(nodes, config, dynamic) do
    Schema.delete_schema([node()]) |> MError.error_description(@identifier)
    start_and_subscribe()

    case try_join(nodes, config) do
      :ok ->
        ready(config, dynamic)

      :pending ->
        Logger.warning(
          "[mishka_installer.mnesia] no cluster node in #{inspect(nodes)} reachable yet; " <>
            "waiting to join when one connects"
        )

        {:ok, %State{essential: config[:essential], status: :pending, dynamic: dynamic}}
    end
  end

  defp ready(config, dynamic) do
    synchronized()
    schedule_health_check()

    {:ok,
     %State{
       tables: local_tables(),
       schemas: schemas(),
       essential: config[:essential],
       status: :synchronized,
       dynamic: dynamic
     }}
  end

  # Connect to `nodes`, become a `disc_copies` member and copy each essential table. Returns `:ok`
  # on a successful join or `:pending` when no node is reachable (we retry from `on_nodeup/2`).
  defp try_join(nodes, config) do
    case MnesiaAssistant.change_config(nodes) do
      {:ok, [_ | _] = connected} ->
        finalize_join(connected, config)

      {:ok, []} ->
        :pending

      {:error, reason} ->
        Logger.error(
          "[mishka_installer.mnesia] cluster join error: #{inspect(reason)}; will retry when a node connects"
        )

        :pending
    end
  end

  defp finalize_join(connected, config) do
    with {:atomic, :ok} <- Table.change_table_copy_type(:schema, node(), :disc_copies),
         :ok <- copy_essential_tables(config[:essential]),
         :ok <- wait_for(config[:essential], config) do
      Logger.info("[mishka_installer.mnesia] joined cluster nodes: #{inspect(connected)}")
      :ok
    else
      other ->
        Logger.error(
          "[mishka_installer.mnesia] join did not complete: #{inspect(other)}; will retry"
        )

        :pending
    end
  end

  ################################################################################
  ######################## (▰˘◡˘▰) Membership (▰˘◡˘▰) #######################
  ################################################################################
  defp on_nodeup(peer, state) do
    config = config()

    cond do
      peer not in peers(config[:cluster_nodes]) ->
        cluster_event(:nodeup, peer, %{action: :ignored})
        state

      peer in db_nodes() ->
        cluster_event(:nodeup, peer, %{action: :already_member})
        notify_cluster_changed(peer)
        state

      state.status == :pending ->
        join_from_pending(peer, config, state)

      true ->
        connect_established(peer, state)
    end
  end

  # We deferred our join at boot; a configured node is finally up — run the full join now.
  defp join_from_pending(peer, config, state) do
    case try_join(peers(config[:cluster_nodes]), config) do
      :ok ->
        cluster_event(:nodeup, peer, %{action: :joined})
        {:ok, new_state} = ready(config, state.dynamic)
        notify_cluster_changed(peer)
        new_state

      :pending ->
        cluster_event(:nodeup, peer, %{action: :pending})
        state
    end
  end

  # We already own the data; pull the new peer into our schema (non-destructive — it then copies
  # what it needs). We never delete a schema here, so an established node can't lose data.
  defp connect_established(peer, state) do
    case MnesiaAssistant.change_config([peer]) do
      {:ok, [_ | _]} ->
        Logger.info("[mishka_installer.mnesia] connected new cluster node: #{inspect(peer)}")
        cluster_event(:nodeup, peer, %{action: :connected})
        notify_cluster_changed(peer)
        %{state | tables: local_tables(), schemas: schemas()}

      {:ok, []} ->
        cluster_event(:nodeup, peer, %{action: :unreachable})
        state

      {:error, reason} ->
        Logger.warning(
          "[mishka_installer.mnesia] could not connect node #{inspect(peer)}: #{inspect(reason)}"
        )

        cluster_event(:nodeup, peer, %{action: {:error, reason}})
        state
    end
  end

  ################################################################################
  ######################## (▰˘◡˘▰) Helpers (▰˘◡˘▰) ##########################
  ################################################################################
  defp already_running?(config) do
    :mnesia.system_info(:is_running) == :yes and
      Path.expand("#{:mnesia.system_info(:directory)}") == Path.expand(config[:mnesia_dir]) and
      Enum.all?(config[:essential], &(&1 in local_tables()))
  end

  defp start_and_subscribe() do
    MnesiaAssistant.start() |> MError.error_description(@identifier)
    MnesiaAssistant.subscribe(:system)
  end

  defp copy_essential_tables(essentials) do
    case Enum.filter(essentials, &(copy_essential_table(&1) == :error)) do
      [] -> :ok
      failed -> {:stop, {:essential_table_copy_failed, failed}}
    end
  end

  defp copy_essential_table(item) do
    case Table.add_table_copy(item, node(), :disc_copies) do
      {:atomic, :ok} ->
        table_event(item, :copied)
        :ok

      {:aborted, {:already_exists, _, _}} ->
        table_event(item, :already_loaded)
        :ok

      error ->
        Logger.error(
          "[mishka_installer.mnesia] could not copy table #{inspect(item)}: #{inspect(error)}"
        )

        table_event(item, :error)
        :error
    end
  end

  defp wait_for(tables, config), do: wait_for(tables, config, config[:wait_retries])

  defp wait_for(tables, _config, 0) do
    Logger.critical("[mishka_installer.mnesia] tables still not available: #{inspect(tables)}")
    {:stop, {:mnesia_tables_unavailable, tables}}
  end

  defp wait_for(tables, config, retries) do
    case Table.wait_for_tables(tables, config[:wait_timeout]) do
      :ok ->
        :ok

      {:timeout, remaining} ->
        Logger.warning(
          "[mishka_installer.mnesia] still loading #{inspect(remaining)} (large disc tables?); waiting…"
        )

        wait_for(remaining, config, retries - 1)

      {:error, reason} ->
        Logger.critical("[mishka_installer.mnesia] tables unavailable: #{inspect(reason)}")
        {:stop, {:mnesia_tables_unavailable, reason}}
    end
  end

  defp config() do
    Application.get_env(:mishka_installer, __MODULE__, [])
    |> Keyword.put_new(:mnesia_dir, ".mnesia/#{MishkaInstaller.__information__().env}")
    |> Keyword.put_new(:essential, [Installer, Event])
    |> Keyword.put_new(:cluster_nodes, :auto)
    |> Keyword.put_new(:dynamic_membership, true)
    |> Keyword.put_new(:wait_timeout, @wait_timeout)
    |> Keyword.put_new(:wait_retries, @wait_retries)
  end

  defp peers(:auto), do: []
  defp peers(nodes) when is_list(nodes), do: nodes

  defp configure_dir(dir) do
    Logger.debug("[mishka_installer.mnesia] stopping to (re)load the schema")
    MnesiaAssistant.stop() |> MError.error_description()
    File.mkdir_p(dir) |> MError.error_description(@identifier)
    Application.put_env(:mnesia, :dir, to_charlist(dir))
    :ok
  end

  defp maybe_create_schema() do
    case :mnesia.system_info(:extra_db_nodes) do
      [] -> Schema.create_schema([node()]) |> MError.error_description(@identifier)
      _ -> :ok
    end
  end

  defp create_essential_tables(essentials) do
    case Enum.filter(essentials, &(create_essential_table(&1) == :error)) do
      [] ->
        :ok

      failed ->
        Logger.critical("[mishka_installer.mnesia] essential tables failed: #{inspect(failed)}")
        {:stop, {:essential_table_failed, failed}}
    end
  end

  defp create_essential_table(item) do
    cond do
      item in local_tables() ->
        table_event(item, :already_loaded)
        :ok

      Code.ensure_loaded?(item) and function_exported?(item, :database_config, 0) ->
        item
        |> Table.create_table(item.database_config())
        |> MError.error_description(item)
        |> case do
          {:ok, :atomic} ->
            Logger.debug("[mishka_installer.mnesia] essential table created: #{inspect(item)}")
            table_event(item, :created)
            :ok

          {:error, {:aborted, {:already_exists, _}}, _} ->
            table_event(item, :already_exists)
            :ok

          error ->
            Logger.error(
              "[mishka_installer.mnesia] could not create table #{inspect(item)}: #{inspect(error)}"
            )

            table_event(item, :error)
            :error
        end

      true ->
        Logger.error(
          "[mishka_installer.mnesia] essential #{inspect(item)} exports no database_config/0"
        )

        :error
    end
  end

  defp synchronized() do
    Logger.info("[mishka_installer.mnesia] tables synchronized on #{inspect(node())}")

    MishkaInstaller.broadcast("mnesia", :synchronized, %{
      identifier: @identifier,
      local_tables: local_tables(),
      schemas: schemas()
    })

    :telemetry.execute(
      @telemetry ++ [:synchronized],
      %{system_time: System.system_time()},
      %{node: node(), tables: local_tables()}
    )
  end

  defp table_event(table, status) do
    :telemetry.execute(
      @telemetry ++ [:table],
      %{system_time: System.system_time()},
      %{table: table, status: status}
    )
  end

  # Tell the cluster that membership changed so the event layer can rebuild any compiled module that
  # drifted while a node was away (cheap: a recompile only happens for events whose plugin set
  # actually changed). Broadcast on the "mnesia" channel — we don't reach up into the event layer.
  defp notify_cluster_changed(peer) do
    MishkaInstaller.broadcast("mnesia", :cluster_changed, %{node: node(), peer: peer})
  end

  defp cluster_event(kind, peer, meta) do
    :telemetry.execute(
      @telemetry ++ [:cluster, kind],
      %{system_time: System.system_time()},
      Map.merge(%{node: node(), peer: peer}, meta)
    )
  end

  defp monitor_nodes(true) do
    _ = :net_kernel.monitor_nodes(true)
    :ok
  end

  defp monitor_nodes(false), do: :ok

  defp schedule_health_check() do
    if MishkaInstaller.__information__().env != :test do
      Process.send_after(self(), :health_check, @health_interval)
    end
  end

  defp local_tables(), do: :mnesia.system_info(:local_tables)

  defp db_nodes(), do: :mnesia.system_info(:db_nodes)
end
