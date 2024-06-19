defmodule MishkaInstaller.MnesiaRepo do
  @moduledoc false
  use GenServer
  require Logger
  alias MishkaInstaller.Event.Event
  alias MnesiaAssistant.Error, as: MError

  @env_mod Mix.env()
  # I got the basic idea from https://github.com/processone/ejabberd
  @identifier :mishka_mnesia_repo
  ####################################################################################
  ########################## (▰˘◡˘▰) Schema (▰˘◡˘▰) ############################
  ####################################################################################
  defmodule State do
    defstruct tables: [], schemas: [], status: :started
  end

  ################################################################################
  ######################## (▰˘◡˘▰) Init data (▰˘◡˘▰) #######################
  ################################################################################
  @spec start_link() :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(_state \\ []) do
    Logger.info(
      "Identifier: #{inspect(@identifier)} ::: MnesiaMessage: Mnesia's initial valuation process has begun."
    )

    Logger.info(
      "Identifier: #{inspect(@identifier)} ::: Stopping Mnesia to start and load Schema files."
    )

    MnesiaAssistant.stop() |> MError.error_description()

    Logger.info(
      "Identifier: #{inspect(@identifier)} ::: Creating the parent path of Mnesia if it doesn't exist."
    )

    Logger.info(
      "Identifier: #{inspect(@identifier)} ::: Placing Mnesia address of the generator in the mentioned system variable."
    )

    mnesia_dir = ".mnesia" <> "/#{@env_mod}"
    config = Application.get_env(:mishka, Mishka.MnesiaRepo, mnesia_dir: mnesia_dir)
    File.mkdir_p(config[:mnesia_dir]) |> MError.error_description(@identifier)
    Application.put_env(:mnesia, :dir, config[:mnesia_dir] |> to_charlist)

    my_node = node()
    db_nodes = :mnesia.system_info(:db_nodes)

    if my_node in db_nodes do
      case MnesiaAssistant.Information.system_info(:extra_db_nodes) do
        [] ->
          MnesiaAssistant.Schema.create_schema([my_node]) |> MError.error_description(@identifier)

        _ ->
          :ok
      end

      MnesiaAssistant.start() |> MError.error_description(@identifier)

      Logger.debug(
        "Identifier: #{inspect(@identifier)} ::: Waiting for Mnesia tables synchronization..."
      )

      MnesiaAssistant.Table.wait_for_tables(:mnesia.system_info(:local_tables), :infinity)

      Logger.info("Identifier: #{inspect(@identifier)} ::: Mnesia tables Synchronized...")

      essential_tables(Keyword.get(config, :essential, [Event]))

      MishkaInstaller.broadcast("mnesia", :synchronized, %{
        identifier: :mishka_mnesia_repo,
        local_tables: :mnesia.system_info(:local_tables),
        schemas: schemas()
      })

      Process.send_after(__MODULE__, :health_check, 1000)

      {:ok, %State{tables: :mnesia.system_info(:local_tables), schemas: schemas()}}
    else
      Logger.critical(
        "Identifier: #{inspect(@identifier)} ::: Node name mismatch: I'm #{my_node}, the database is owned by #{db_nodes}"
      )

      {:stop, :node_name_mismatch}
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Callback (▰˘◡˘▰) ##########################
  ####################################################################################
  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(request, from, state) do
    Logger.warning(
      "Identifier: #{inspect(@identifier)} ::: Unexpected call from #{inspect(from)}: #{inspect(request)}"
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("Identifier: #{inspect(@identifier)} ::: Unexpected cast: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  if Mix.env() != :test do
    def handle_info(:health_check, state) do
      # TODO: this function can have some checker
      Process.send_after(__MODULE__, :health_check, 1000)

      MishkaInstaller.broadcast("mnesia", Map.get(state, :status), %{
        identifier: :mishka_mnesia_repo,
        local_tables: :mnesia.system_info(:local_tables),
        schemas: schemas()
      })

      {:noreply, state}
    end
  else
    def handle_info(:health_check, state) do
      {:noreply, state}
    end
  end

  def handle_info(info, state) do
    Logger.warning("Identifier: #{inspect(@identifier)} ::: Unexpected info: #{inspect(info)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  @spec schema_path() :: binary()
  def schema_path() do
    dir =
      case System.get_env("Mishka_MNESIA_SCHEMA") do
        nil -> :mnesia.system_info(:directory)
        path -> path
      end

    Path.join(dir, "mishka.schema")
  end

  @spec schemas() :: list()
  def schemas() do
    Enum.flat_map(:mnesia.system_info(:tables), fn
      :schema ->
        []

      tab ->
        [
          {tab,
           [
             {:storage_type, :mnesia.table_info(tab, :storage_type)},
             {:local_content, :mnesia.table_info(tab, :local_content)}
           ]}
        ]
    end)
  end

  defp essential_tables(nil), do: nil

  defp essential_tables(essentials) do
    essentials
    |> Enum.map(fn item ->
      with true <- item not in :mnesia.system_info(:local_tables),
           true <- Code.ensure_loaded?(item),
           function_exported?(item, :database_config, 0) do
        MnesiaAssistant.Table.create_table(item, item.database_config())
        |> MError.error_description(item)
        |> case do
          {:ok, :atomic} ->
            Logger.info("Identifier: #{inspect(item)} ::: Mnesia table Synchronized...")

            Logger.info(
              "Identifier: #{inspect(item)} ::: Mnesia essentials table synchronization..."
            )

            MnesiaAssistant.Table.wait_for_tables([item], :infinity)

            Logger.info(
              "Identifier: #{inspect(item)} ::: Mnesia essentials table Synchronized..."
            )

          {:error, {:aborted, {:already_exists, module}}, _msg} ->
            Logger.info("Identifier: #{inspect(module)} ::: Mnesia tables already exists...")

          error ->
            Logger.error("Identifier: #{inspect(item)} ::: Source: #{inspect(error)}")
        end
      end
    end)
  end
end
