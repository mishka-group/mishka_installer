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

  def deps(app, custom_command \\ []) do
    GenServer.cast(__MODULE__, {:deps, app, custom_command})
  end

  @impl true
  def init(_state) do
    Logger.info("OTP Dependencies changes protector server was started")
    {:ok, %{data: nil, ref: nil}, {:continue, :check_json}}
  end

  @impl true
  def handle_continue(:check_json, state) do
    Process.send_after(self(), :check_json, @re_check_json_time)
    MishkaInstaller.Dependency.subscribe()
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_json, state) do
    if Mix.env() not in [:dev, :test], do: Logger.info("OTP Dependencies changes protector Cache server was valued by JSON.")
    Process.send_after(self(), :check_json, @re_check_json_time)
    new_state =
      if is_nil(state.ref) do
        Map.merge(state, %{data: json_check_and_create()})
      else
        state
      end
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:ok, :dependency, _action, _repo_data}, state) do
    DepHandler.extensions_json_path()
    |> File.rm_rf()
    {:noreply, Map.merge(state, %{data: json_check_and_create()})}
  end

  @impl true
  def handle_info({ref, answer}, %{ref: ref} = state) do
    # The task completed successfully
    {:noreply, Map.merge(state, %{data: update_dependency_type(answer, state) || state, ref: nil, app: nil})}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _status}, state) do
    {:noreply, %{state | ref: nil}}
  end

  def handle_info({:do_compile, app, custom_command}, state) do
    new_state =
      if is_nil(state.ref) do
        task =
          Task.Supervisor.async_nolink(DepChangesProtectorTask, fn ->
            MishkaInstaller.Installer.RunTimeSourcing.deps(custom_command)
          end)
        {:noreply, Map.merge(state, %{ref: task.ref, app: app})}
      else
        Process.send_after(self(), {:do_compile, app, custom_command}, @re_check_json_time)
        {:noreply, state}
      end
      new_state
  end

  @impl true
  def handle_call({:push, app: app, status: status}, _from, state) do
    new_state =
      case Enum.find(state.data, & &1.app == app) do
        nil ->
          new_app = %{app: app, status: status, time: DateTime.utc_now}
          {:reply, new_app, Map.merge(state, %{data: state.data ++ [new_app]})}
        _ ->
          {:reply, {:duplicate, app}, state}
      end
    new_state
  end

  @impl true
  def handle_call({:get, app}, _from, state) do
    {:reply, Enum.find(state.data, & &1.app == app), state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:pop, app}, _from, state) do
    new_state = Enum.reject(state.data, & &1.app == app)
    {:reply, new_state, %{state | data: new_state}}
  end

  @impl true
  def handle_cast({:deps, app, custom_command}, state) do
    Process.send_after(self(), {:do_compile, app, custom_command}, 100)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:clean, _state) do
    {:noreply, []}
  end

  @spec is_dependency_compiling? :: boolean
  def is_dependency_compiling?(), do: if(is_nil(get().ref), do: false, else: true)

  # For now, we decided to remove and re-create JSON file to prevent user not to delete or wrong edit manually
  defp json_check_and_create() do
    File.rm_rf(DepHandler.extensions_json_path())
    {:ok, :check_or_create_deps_json, json} = DepHandler.check_or_create_deps_json()
    {:ok, :read_dep_json, data} = DepHandler.read_dep_json(json)
    Enum.filter(data, &(&1["dependency_type"] == "force_update"))
    |> Enum.map(&(%{app: &1["app"], status: &1["dependency_type"], time: DateTime.utc_now}))
  rescue
    _e -> []
  end

  defp update_dependency_type(answer, state, dependency_type \\ "none") do
    with {:compile_status, false} <- {:compile_status, Enum.any?(answer, & &1.status != 0)},
         {:ok, :change_dependency_type_with_app, _repo_data} <- MishkaInstaller.Dependency.change_dependency_type_with_app(state.app, dependency_type) do

          json_check_and_create()
    else
      {:compile_status, true} ->
        MishkaInstaller.dependency_activity("compiling", %{state: answer}, "high")
      {:error, :change_dependency_type_with_app, :dependency, :not_found} ->
        MishkaInstaller.dependency_activity("compiling", %{state: answer, action: "no_app_found"}, "high")
      {:error, :change_dependency_type_with_app, :dependency, repo_error} ->
        MishkaInstaller.dependency_activity("compiling", %{state: answer, action: "edit", error: repo_error}, "high")
    end
  end
end
