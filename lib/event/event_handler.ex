defmodule MishkaInstaller.Event.EventHandler do
  use GenServer
  require Logger
  alias MishkaInstaller.Event.Event

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
    {:ok, Keyword.merge([running: [], queues: QueueAssistant.new(), status: :starting], state)}
  end

  ####################################################################################
  ######################## (▰˘◡˘▰) Public APIs (▰˘◡˘▰) #########################
  ####################################################################################
  def do_compile(event, status) do
    GenServer.cast(__MODULE__, {:do_compile, event, status})
  end

  def get_running() do
  end

  def get_queues() do
  end

  def do_clean() do
  end

  def change_status() do
  end

  def get_status() do
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Callback (▰˘◡˘▰) ##########################
  ####################################################################################
  @impl true
  def handle_cast(:do_compile, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:do_compile, _event, status}, state) do
    MishkaInstaller.broadcast("event", status, %{})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:change_status, _status}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:do_clean, _status}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(_action, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_running, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_queues, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(_action, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(%{status: :synchronized, channel: "mnesia"}, state) do
    new_state =
      case Event.start() do
        {:ok, _sorted_events} ->
          :persistent_term.put(:event_status, "ready")
          Logger.debug("Identifier: #{inspect(__MODULE__)} ::: Plugins are Synchronized...")
          MishkaInstaller.broadcast("mnesia", :event_status, "ready")
          Keyword.merge(state, status: :synchronized)

        _ ->
          state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_action, state) do
    {:noreply, state}
  end
end
