defmodule MishkaInstaller.Installer.DepChangesProtector do
  use GenServer
  require Logger

  @spec start_link(list()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def push(app, status) do
    GenServer.call(__MODULE__, {:push, app: app, status: status})
  end

  def get(app) do
    GenServer.call(__MODULE__, {:get, app})
  end

  def get() do
    GenServer.call(__MODULE__, :get)
  end

  def pop(app) do
    GenServer.call(__MODULE__, {:pop, app})
  end

  def clean() do
    GenServer.cast(__MODULE__, :clean)
  end

  @impl true
  def init(stack) do
    Logger.info("OTP Dependencies changes protector Cache server was started")
    {:ok, stack, {:continue, :check_json}}
  end

  @impl true
  def handle_continue(:check_json, state) do
    Process.send_after(self(), :check_json, 10_000)
    {:noreply,state}
  end

  @impl true
  def handle_info(:check_json, _state) do
    Logger.info("OTP Dependencies changes protector Cache server was valued by JSON.")
    new_state =
      with {:ok, :check_or_create_deps_json, _json} <- MishkaInstaller.Installer.DepHandler.check_or_create_deps_json(),
           {:ok, :read_dep_json, data} <- MishkaInstaller.Installer.DepHandler.read_dep_json() do
            data
            |> Enum.filter(&(&1["dependency_type"] == "soft_update"))
            |> Enum.map(&(%{app: &1["app"], status: &1["dependency_type"], time: DateTime.utc_now}))
      else
        _ -> []
      end
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:push, app: app, status: status}, _from, state) do
    new_state =
      case Enum.find(state, & &1.app == app) do
        nil ->
          new_app = %{app: app, status: status, time: DateTime.utc_now}
          {:reply, new_app, state ++ [new_app]}
        _ ->

          {:reply, {:duplicate, app}, state}
      end
    new_state
  end

  @impl true
  def handle_call({:get, app}, _from, state) do
    {:reply, Enum.find(state, & &1.app == app), state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:pop, app}, _from, state) do
    new_state = Enum.reject(state, & &1.app == app)
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_cast(:clean, _state) do
    {:noreply, []}
  end

  def check_josn_file_exist?() do
    # TODO: Check if extension json file does not exist, create it with database
  end

  def is_there_update?() do
    # TODO: Check is there update from a developer json url, and get it from plugin/componnet mix file, Consider queue
  end

  def is_dependency_compiling?() do
    # TODO: Create queue for installing multi deps, and compiling, check oban: https://github.com/sorentwo/oban
  end
end
