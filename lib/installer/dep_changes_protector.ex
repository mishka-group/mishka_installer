defmodule MishkaInstaller.Installer.DepChangesProtector do
  @moduledoc """
    This module helps you to protect the extension.json file and every action like add or delete or even edit a dependency is happened,
    it can handle it and create new state.
  """
  use GenServer, restart: :permanent
  require Logger
  @re_check_json_time 10_000
  @module "dep_changes_protector"
  alias MishkaInstaller.Installer.DepHandler
  alias MishkaInstaller.Dependency

  @spec start_link(list()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec push(map(), String.t() | atom()) :: map()
  def push(app, status) do
    GenServer.call(__MODULE__, {:push, app: app, status: status})
  end

  @spec get(String.t()) :: map()
  def get(app) do
    GenServer.call(__MODULE__, {:get, app})
  end

  @spec get :: map()
  def get() do
    GenServer.call(__MODULE__, :get)
  end

  @spec pop(String.t()) :: map()
  def pop(app) do
    GenServer.call(__MODULE__, {:pop, app})
  end

  @spec clean :: :ok
  def clean() do
    GenServer.cast(__MODULE__, :clean)
  end

  @spec deps(String.t(), atom()) :: :ok
  def deps(app, type \\ :port) do
    GenServer.cast(__MODULE__, {:deps, app, type})
  end

  @impl true
  def init(_state) do
    Logger.info("OTP Dependencies changes protector server was started")
    {:ok, %{data: nil, ref: nil}, {:continue, :check_json}}
  end

  @impl true
  def handle_continue(:check_json, state) do
    check_custom_pubsub_loaded(state)
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
  def handle_info({_ref, {:installing_app, app_name, _move_apps, app_res}}, state) do
    # TODO: problem with dependency_activity to store output of errors
    project_path = MishkaInstaller.get_config(:project_path) || File.cwd!()
    case app_res do
      {:ok, :application_ensure} ->
        [Path.join(project_path, ["deps/", "#{app_name}", "/_build"]), Path.join(project_path, ["deps/", "#{app_name}", "/deps"])]
        |> Enum.map(& (File.rm_rf(&1)))
        notify_subscribers({:ok, app_res, app_name})
      {:error, do_runtime, app, operation: operation, output: output} ->
        notify_subscribers({:error, app_res, "#{app}"})
        MishkaInstaller.dependency_activity(%{state: [{:error, do_runtime, "#{app}", operation: operation, output: output}]}, "high")
      {:error, do_runtime, ensure, output} ->
        notify_subscribers({:error, app_res, app_name})
        MishkaInstaller.dependency_activity(%{state: [{:error, do_runtime, app_name, operation: ensure, output: output}]}, "high")
    end
    {:noreply, state}
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

  @impl true
  def handle_info({:do_compile, app, type}, state) do
    # TODO: Can be replaced with oban, Build queues for compiling and installing dependencies
    new_state =
      if is_nil(state.ref) do
        task =
          Task.Supervisor.async_nolink(DepChangesProtectorTask, fn ->
            MishkaInstaller.Installer.RunTimeSourcing.do_deps_compile(app, type)
          end)
        {:noreply, Map.merge(state, %{ref: task.ref, app: app})}
      else
        Process.send_after(self(), {:do_compile, app}, @re_check_json_time)
        {:noreply, state}
      end
      new_state
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.info("We are waiting for your custom pubsub is loaded")
    check_custom_pubsub_loaded(state)
  end

  @impl true
  def handle_info(_param, state) do
    # TODO: it should be loged
    Logger.info("We have an uncontrolled output")
    {:noreply, state}
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
  def handle_cast({:deps, app, type}, state) do
    Process.send_after(self(), {:do_compile, app, type}, 100)
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

  def update_dependency_type(answer, state, dependency_type \\ "none") do
    with {:ok, :do_deps_compile, app_name} <- answer,
         {:ok, :change_dependency_type_with_app, _repo_data} <- Dependency.change_dependency_type_with_app(app_name, dependency_type) do
          json_check_and_create()
          with {:ok, :compare_installed_deps_with_app_file, apps_list} <- DepHandler.compare_installed_deps_with_app_file("#{app_name}") do
            Task.Supervisor.async_nolink(DepChangesProtectorTask, fn ->
              MishkaInstaller.Installer.RunTimeSourcing.do_runtime(String.to_atom(state.app), :uninstall)
              {
                :installing_app,
                app_name,
                DepHandler.move_and_replace_compiled_app_build(apps_list),
                MishkaInstaller.Installer.RunTimeSourcing.do_runtime(String.to_atom(state.app), :add)
              }
            end)
          end
    else
      {:error, :do_deps_compile, app, operation: _operation, output: output} ->
        with {:ok, :get_record_by_field, :dependency, record_info} <- Dependency.show_by_name(app) do
          Dependency.delete(record_info.id)
        end
        notify_subscribers({:error, output, app})
        MishkaInstaller.dependency_activity(%{state: [answer]}, "high")
      {:error, :change_dependency_type_with_app, :dependency, :not_found} ->
        MishkaInstaller.dependency_activity(%{state: [answer], action: "no_app_found"}, "high")
      {:error, :change_dependency_type_with_app, :dependency, repo_error} ->
        MishkaInstaller.dependency_activity(%{state: [answer], action: "edit", error: repo_error}, "high")
    end
  end

  defp check_custom_pubsub_loaded(state) do
    custom_pubsub = MishkaInstaller.get_config(:pubsub)
    cond do
      !is_nil(custom_pubsub) && is_nil(Process.whereis(custom_pubsub)) -> {:noreply, state, 100}
      true ->
        Process.send_after(self(), :check_json, @re_check_json_time)
        MishkaInstaller.Dependency.subscribe()
        {:noreply, state}
    end
  end

  @spec subscribe :: :ok | {:error, {:already_registered, pid}}
  def subscribe do
    Phoenix.PubSub.subscribe(MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub, @module)
  end

  @spec notify_subscribers({atom(), any, String.t() | atom()}) :: :ok | {:error, any}
  def notify_subscribers({status, answer, app}) do
    Phoenix.PubSub.broadcast(MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub, @module , {status, String.to_atom(@module), answer, app})
  end
end
