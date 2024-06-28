defmodule MishkaInstaller.Installer.CompileHandler do
  @moduledoc false
  use GenServer
  require Logger
  require Logger
  alias MishkaInstaller.Installer.{Installer, LibraryHandler}
  ################################################################################
  ######################## (▰˘◡˘▰) Init data (▰˘◡˘▰) #######################
  ################################################################################
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  @spec init(keyword()) :: {:ok, keyword()}
  def init(state \\ []) do
    MishkaInstaller.subscribe("mnesia")
    {:ok, Keyword.merge(state, running: [], queues: QueueAssistant.new())}
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
    queues = Keyword.get(state, :queues, QueueAssistant.new())
    new_state = Keyword.merge(state, queues: QueueAssistant.insert(queues, event))

    send(self(), :run_queues)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:do_clean, state) do
    new_state = Keyword.merge(state, running: [], queues: QueueAssistant.new())
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
    queues = Keyword.get(state, :queues, QueueAssistant.new())

    new_state =
      if length(running) == 0 and !QueueAssistant.empty?(queues) do
        case QueueAssistant.out(queues) do
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
        output = Installer.install(List.first(running))

        case output do
          {:ok, %{extension: extension} = data} ->
            Logger.info(
              "Identifier: #{inspect(__MODULE__)} ::: The desired library(#{extension.app}) was successfully compiled and activated"
            )

            MishkaInstaller.broadcast("installer", :install, data)

          {:error, error} ->
            Logger.error(
              "Identifier: #{inspect(__MODULE__)} ::: Compiling error! ::: Source: #{error}"
            )
        end

        send(self(), :run_queues)
        Keyword.merge(state, running: [])
      else
        state
      end

    {:noreply, new_state}
  end

  def handle_info(%{status: :synchronized, channel: "mnesia"}, state) do
    errors =
      Installer.get()
      |> Enum.reduce([], fn item, acc ->
        with :ok <- LibraryHandler.prepend_compiled_apps(item.prepend_paths),
             :ok <- LibraryHandler.unload(String.to_atom(item.app)),
             :ok <- LibraryHandler.application_ensure(String.to_atom(item.app)) do
          acc
        else
          error -> acc ++ [{item.app, error}]
        end
      end)

    if errors == [] do
      :persistent_term.put(:compile_status, "ready")
      MishkaInstaller.broadcast("mnesia", :compile_synchronized, %{identifier: :compile_handler})
      Logger.debug("Identifier: #{inspect(__MODULE__)} ::: Run-time apps are Synchronized...")
    else
      Logger.error(
        "Identifier: #{inspect(__MODULE__)} ::: Run-time apps Synchronizing have errors ::: Source: #{errors}"
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_action, state) do
    {:noreply, state}
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
end
