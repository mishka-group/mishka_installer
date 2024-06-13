defmodule MishkaInstaller.Event.EventHandler do
  use GenServer
  require Logger

  ################################################################################
  ######################## (▰˘◡˘▰) Init data (▰˘◡˘▰) #######################
  ################################################################################
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  @spec init(keyword()) :: {:ok, keyword()}
  def init(state \\ []) do
    {:ok, Keyword.merge([running: [], queues: [], status: :starting], state)}
  end

  ####################################################################################
  ######################## (▰˘◡˘▰) Public APIs (▰˘◡˘▰) #########################
  ####################################################################################
  def do_compile() do
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
  def handle_cast({:do_compile, _event}, state) do
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
  def handle_info(_action, state) do
    {:noreply, state}
  end
end
