defmodule MishkaInstaller.MnesiaRepo do
  @moduledoc """
  Boots and supervises the [Mnesia](https://www.erlang.org/doc/man/mnesia) store used by
  `MishkaInstaller`.

  On start it (re)configures the Mnesia directory, creates the schema, starts Mnesia, waits for the
  local tables, creates the essential tables, and broadcasts `:synchronized` on the `"mnesia"`
  PubSub channel so the event and installer layers can come online.

  ## Configuration

  Configure under the `:mishka_installer` application env, keyed by this module:

  ```elixir
  config :mishka_installer, MishkaInstaller.MnesiaRepo,
    mnesia_dir: "/var/lib/my_app/mnesia",
    essential: [MishkaInstaller.Event.Event, MishkaInstaller.Installer.Installer],
    cluster_nodes: :auto,
    wait_timeout: 60_000,
    wait_retries: 5
  ```

  - `:mnesia_dir` — where Mnesia stores its files. Defaults to `".mnesia/<env>"` under the project.
  - `:essential` — modules whose `database_config/0` defines a table to create on boot. Defaults to
    `[MishkaInstaller.Installer.Installer, MishkaInstaller.Event.Event]`.
  - `:cluster_nodes` — peers to join the Mnesia cluster. `:auto` (default) uses the already
    distribution-connected nodes (`Node.list/0`), so a cluster formed by `libcluster`/`Node.connect`
    is joined automatically — no static list needed. Pass an explicit list to override, or `[]` to
    stay standalone. On join, this node connects, makes its schema `disc_copies` and keeps a local
    `disc_copies` copy of each essential table. Nodes that connect **after** boot are handled in the
    cluster phase (monitoring `:nodeup`), not at boot.
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
    `:status` (`:created` | `:already_exists` | `:already_loaded` | `:error`).
  - `[:mishka_installer, :mnesia, :synchronized]` — after the boot broadcast. Metadata: `:node`,
    `:tables`.
  - `[:mishka_installer, :mnesia, :health_check]` — periodic. Measurements: `:table_count`,
    `:schema_count`. Metadata: `:node`, `:healthy?`, `:missing`.
  """
  use GenServer
  require Logger
  alias MishkaInstaller.Event.Event
  alias MishkaInstaller.Installer.Installer
  alias MishkaInstaller.MnesiaAssistant
  alias MishkaInstaller.MnesiaAssistant.{Information, Schema, Table}
  alias MishkaInstaller.MnesiaAssistant.Error, as: MError

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
            status: atom()
          }
    defstruct tables: [], schemas: [], essential: [], status: :started
  end

  ################################################################################
  ######################## (▰˘◡˘▰) Public API (▰˘◡˘▰) #######################
  ################################################################################
  @doc "Starts the Mnesia repository process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @doc "Returns the current repository `t:MishkaInstaller.MnesiaRepo.State.t/0`."
  @spec state() :: State.t()
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

    unless healthy?,
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

  def handle_info(info, state) do
    Logger.warning("[mishka_installer.mnesia] unexpected info: #{inspect(info)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  @impl true
  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  ################################################################################
  ######################## (▰˘◡˘▰) Helpers (▰˘◡˘▰) ##########################
  ################################################################################
  defp bootstrap() do
    config = config()

    if already_running?(config) do
      Logger.debug(
        "[mishka_installer.mnesia] already running on #{inspect(node())}; re-announcing"
      )

      synchronized()
      schedule_health_check()
      {:ok, initial_state(config)}
    else
      full_boot(config)
    end
  end

  defp full_boot(config) do
    configure_dir(config[:mnesia_dir])
    essential = config[:essential]
    cluster = cluster_nodes(config)

    with :ok <- start_or_join(cluster),
         :ok <- wait_for(local_tables(), config),
         :ok <- setup_essential_tables(essential, cluster),
         :ok <- wait_for(essential, config) do
      synchronized()
      schedule_health_check()
      {:ok, initial_state(config)}
    end
  end

  defp initial_state(config) do
    %State{tables: local_tables(), schemas: schemas(), essential: config[:essential]}
  end

  defp already_running?(config) do
    :mnesia.system_info(:is_running) == :yes and
      Path.expand("#{:mnesia.system_info(:directory)}") == Path.expand(config[:mnesia_dir]) and
      Enum.all?(config[:essential], &(&1 in local_tables()))
  end

  defp start_or_join([]) do
    if node() in :mnesia.system_info(:db_nodes) do
      maybe_create_schema()
      MnesiaAssistant.start() |> MError.error_description(@identifier)
      :ok
    else
      Logger.critical(
        "[mishka_installer.mnesia] node mismatch: #{inspect(node())} owns a different schema dir"
      )

      {:stop, :node_name_mismatch}
    end
  end

  defp start_or_join(nodes) do
    MnesiaAssistant.start() |> MError.error_description(@identifier)

    case :mnesia.change_config(:extra_db_nodes, nodes) do
      {:ok, connected} when connected != [] ->
        :mnesia.change_table_copy_type(:schema, node(), :disc_copies)
        Logger.info("[mishka_installer.mnesia] joined cluster nodes: #{inspect(connected)}")
        :ok

      {:ok, []} ->
        Logger.critical(
          "[mishka_installer.mnesia] could not reach any cluster node in #{inspect(nodes)}"
        )

        {:stop, :no_cluster_nodes_reachable}

      {:error, reason} ->
        {:stop, {:cluster_join_failed, reason}}
    end
  end

  defp setup_essential_tables(essentials, []), do: create_essential_tables(essentials)

  defp setup_essential_tables(essentials, _cluster) do
    case Enum.filter(essentials, &(copy_essential_table(&1) == :error)) do
      [] -> :ok
      failed -> {:stop, {:essential_table_copy_failed, failed}}
    end
  end

  defp copy_essential_table(item) do
    case :mnesia.add_table_copy(item, node(), :disc_copies) do
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
    |> Keyword.put_new(:wait_timeout, @wait_timeout)
    |> Keyword.put_new(:wait_retries, @wait_retries)
  end

  defp cluster_nodes(config) do
    case config[:cluster_nodes] do
      :auto -> Node.list()
      nodes when is_list(nodes) -> nodes
    end
  end

  defp configure_dir(dir) do
    Logger.debug("[mishka_installer.mnesia] stopping to (re)load the schema")
    MnesiaAssistant.stop() |> MError.error_description()
    File.mkdir_p(dir) |> MError.error_description(@identifier)
    Application.put_env(:mnesia, :dir, to_charlist(dir))
    :ok
  end

  defp maybe_create_schema() do
    case Information.system_info(:extra_db_nodes) do
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

  defp schedule_health_check() do
    if MishkaInstaller.__information__().env != :test do
      Process.send_after(self(), :health_check, @health_interval)
    end
  end

  defp local_tables(), do: :mnesia.system_info(:local_tables)
end
