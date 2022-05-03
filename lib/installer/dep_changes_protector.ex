defmodule MishkaInstaller.Installer.DepChangesProtector do
  use GenServer
  require Logger
  @re_check_json_time 10_000
  alias MishkaInstaller.Installer.DepHandler

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
    Process.send_after(self(), :check_json, @re_check_json_time)
    MishkaInstaller.Dependency.subscribe()
    {:noreply,state}
  end

  @impl true
  def handle_info(:check_json, _state) do
    if Mix.env() not in [:dev, :test], do: Logger.info("OTP Dependencies changes protector Cache server was valued by JSON.")
    Process.send_after(self(), :check_json, @re_check_json_time)
    {:noreply, json_check_and_create()}
  end

  @impl true
  def handle_info({:ok, :dependency, _action, _repo_data}, state) do
    MishkaInstaller.Installer.DepHandler.extensions_json_path()
    |> File.rm_rf()
    json_check_and_create()
    {:noreply, state}
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

  def is_there_update?() do
    # TODO: Check is there update from a developer json url, and get it from plugin/componnet mix file, Consider queue
  end

  def is_dependency_compiling?() do
    # TODO: Create queue for installing multi deps, and compiling, check oban: https://github.com/sorentwo/oban
  end

  defp json_check_and_create() do
    with {:ok, :check_or_create_deps_json, json} <- DepHandler.check_or_create_deps_json(),
           {:ok, :read_dep_json, data} <- DepHandler.read_dep_json(json) do
            data
            |> Enum.filter(&(&1["dependency_type"] == "force_update"))
            |> Enum.map(&(%{app: &1["app"], status: &1["dependency_type"], time: DateTime.utc_now}))
      else
        _ ->
          # TODO: send an activity as error log
          []
      end
  end
end
