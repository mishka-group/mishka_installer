defmodule MishkaInstaller.Installer.CompileHandler do
  @moduledoc """
  Serialises runtime library installs and replays previously installed libraries on boot.

  Installs are queued and run one at a time (installing mutates global VM state — the code path,
  loaded modules and started apps — so it must not run concurrently). When the Mnesia store is
  synchronized, every persisted `MishkaInstaller.Installer.Installer` record is re-activated
  (re-added to the code path and started), fault-isolated per app.

  ## Telemetry

  - `[:mishka_installer, :installer, :install]` — emitted after an install. Metadata: `:app`,
    `:result` (`:ok` | `:error`).
  - `[:mishka_installer, :installer, :replay]` — emitted per app re-activated on boot. Metadata:
    `:app`, `:result` (`:ok` | `:error`).
  """
  use GenServer
  require Logger
  alias MishkaInstaller.Installer.{Installer, LibraryHandler}

  @telemetry [:mishka_installer, :installer]

  ################################################################################
  ######################## (▰˘◡˘▰) Init data (▰˘◡˘▰) #######################
  ################################################################################
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  @spec init(keyword()) :: {:ok, keyword()}
  def init(state \\ []) do
    Logger.metadata(domain: [:mishka_installer, :installer])
    MishkaInstaller.subscribe("mnesia")
    {:ok, Keyword.merge(state, running: [], queues: MishkaInstaller.QueueAssistant.new())}
  end

  ####################################################################################
  ######################## (▰˘◡˘▰) Public APIs (▰˘◡˘▰) #########################
  ####################################################################################
  @spec do_compile(Installer.t(), atom()) :: :ok
  def do_compile(event, status) do
    GenServer.cast(__MODULE__, {:do_compile, event, status})
  end

  @spec get() :: keyword()
  def get() do
    GenServer.call(__MODULE__, :get)
  end

  @spec do_clean() :: :ok
  def do_clean() do
    GenServer.cast(__MODULE__, :do_clean)
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Callback (▰˘◡˘▰) ##########################
  ####################################################################################
  @impl true
  def handle_cast({:do_compile, event, status}, state) do
    MishkaInstaller.broadcast("event", status, %{})
    queues = Keyword.get(state, :queues, MishkaInstaller.QueueAssistant.new())
    new_state = Keyword.merge(state, queues: MishkaInstaller.QueueAssistant.insert(queues, event))

    send(self(), :run_queues)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:do_clean, state) do
    new_state = Keyword.merge(state, running: [], queues: MishkaInstaller.QueueAssistant.new())
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(_action, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(_action, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:run_queues, state) do
    running = Keyword.get(state, :running, [])
    queues = Keyword.get(state, :queues, MishkaInstaller.QueueAssistant.new())

    new_state =
      if length(running) == 0 and !MishkaInstaller.QueueAssistant.empty?(queues) do
        case MishkaInstaller.QueueAssistant.out(queues) do
          {:empty, _} ->
            state

          {{:value, value}, new_queues} ->
            send(self(), :do_running)
            Keyword.merge(state, running: [value], queues: new_queues)
        end
      else
        state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:do_running, state) do
    running = Keyword.get(state, :running, [])

    new_state =
      if length(running) != 0 do
        case Installer.install(List.first(running)) do
          {:ok, %{extension: extension} = data} ->
            Logger.info("[mishka_installer.installer] #{extension.app} installed and activated")
            MishkaInstaller.broadcast("installer", :install, data)
            telemetry(:install, %{app: extension.app, result: :ok})

          {:error, error} ->
            Logger.error("[mishka_installer.installer] install error: #{inspect(error)}")
            telemetry(:install, %{app: nil, result: :error})
        end

        send(self(), :run_queues)
        Keyword.merge(state, running: [])
      else
        state
      end

    {:noreply, new_state}
  end

  def handle_info(%{status: :synchronized, channel: "mnesia"}, state) do
    Enum.each(Installer.get(), &replay/1)

    :persistent_term.put(:compile_status, "ready")
    MishkaInstaller.broadcast("mnesia", :compile_synchronized, %{identifier: :compile_handler})
    Logger.debug("[mishka_installer.installer] run-time apps synchronized")

    {:noreply, state}
  end

  @impl true
  def handle_info(_action, state) do
    {:noreply, state}
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  defp replay(item) do
    with :ok <- LibraryHandler.prepend_compiled_apps(item.prepend_paths),
         :ok <- LibraryHandler.unload(String.to_atom(item.app)),
         :ok <- LibraryHandler.application_ensure(String.to_atom(item.app)) do
      Logger.debug("[mishka_installer.installer] re-loaded installed app: #{item.app}")
      telemetry(:replay, %{app: item.app, result: :ok})
    else
      error ->
        Logger.error(
          "[mishka_installer.installer] skipped re-loading #{item.app} on boot: #{inspect(error)}"
        )

        telemetry(:replay, %{app: item.app, result: :error})
    end
  end

  defp telemetry(name, metadata) do
    :telemetry.execute(@telemetry ++ [name], %{system_time: System.system_time()}, metadata)
  end
end
