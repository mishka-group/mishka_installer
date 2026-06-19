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
    essential: [MishkaInstaller.Event.Event, MishkaInstaller.Installer.Installer]
  ```

  - `:mnesia_dir` — where Mnesia stores its files. Defaults to `".mnesia/<env>"` under the project.
  - `:essential` — modules whose `database_config/0` defines a table to create on boot. Defaults to
    `[MishkaInstaller.Installer.Installer, MishkaInstaller.Event.Event]`.

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

  @doc "Returns the absolute path of the Mnesia schema file."
  @spec schema_path() :: binary()
  def schema_path() do
    dir = System.get_env("Mishka_MNESIA_SCHEMA") || :mnesia.system_info(:directory)
    Path.join(dir, "mishka.schema")
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
    configure_dir(config[:mnesia_dir])

    if node() in :mnesia.system_info(:db_nodes) do
      maybe_create_schema()
      MnesiaAssistant.start() |> MError.error_description(@identifier)
      Table.wait_for_tables(local_tables(), :infinity)

      essential = config[:essential]
      create_essential_tables(essential)
      synchronized()
      schedule_health_check()

      {:ok, %State{tables: local_tables(), schemas: schemas(), essential: essential}}
    else
      Logger.critical(
        "[mishka_installer.mnesia] node mismatch: #{inspect(node())} is not in #{inspect(:mnesia.system_info(:db_nodes))}"
      )

      {:stop, :node_name_mismatch}
    end
  end

  defp config() do
    Application.get_env(:mishka_installer, __MODULE__, [])
    |> Keyword.put_new(:mnesia_dir, ".mnesia/#{MishkaInstaller.__information__().env}")
    |> Keyword.put_new(:essential, [Installer, Event])
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
    Enum.each(essentials, &create_essential_table/1)
  end

  defp create_essential_table(item) do
    cond do
      item in local_tables() ->
        table_event(item, :already_loaded)

      Code.ensure_loaded?(item) and function_exported?(item, :database_config, 0) ->
        item
        |> Table.create_table(item.database_config())
        |> MError.error_description(item)
        |> case do
          {:ok, :atomic} ->
            Table.wait_for_tables([item], :infinity)
            Logger.debug("[mishka_installer.mnesia] essential table ready: #{inspect(item)}")
            table_event(item, :created)

          {:error, {:aborted, {:already_exists, _}}, _} ->
            table_event(item, :already_exists)

          error ->
            Logger.error(
              "[mishka_installer.mnesia] could not create table #{inspect(item)}: #{inspect(error)}"
            )

            table_event(item, :error)
        end

      true ->
        Logger.warning(
          "[mishka_installer.mnesia] skipping #{inspect(item)}: no database_config/0 exported"
        )

        :ok
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
