defmodule MishkaInstaller.Installer.DepChangesProtector do
  @moduledoc """
  This module serializes how to get and install a library and add it to your system.
  Based on the structure of `MishkaInstaller`, this module should not be called independently.

  - The reason for the indirect call is to make the queue and also to run the processes in the background.
  - For this purpose, two workers have been created for this module, which can handle the update operation and add a library.

  ### Below you can see the graph of connecting this module to another module.

  ```

  +---------------------------------------+
  |                                       |
  |                                       <-----------------------------------+
  | MishkaInstaller.Installer.DepHandler  |                                   |
  |                                       |       +---------------------------+------+
  |                                       |       |                                  |
  +-------------------+-----------------^-+       |                                  |
                      |                 |         |  MishkaInstaller.DepCompileJob   |
                      |                 |         |                                  <-----------+
                      |                 |         |                                  |           |
                      |                 |         +----------------------------------+           |
                      |                 |                                                        |
                      |                 |         +----------------------------------+           |
                      |                 |         |                                  |           |
                      |                 |         |                                  |           |
                      |                 |         |  MishkaInstaller.DepUpdateJob    |           |
                      |                 +---------+                                  |           |
                      |                           |                                  |           |
                      |                           +-^--------------------------------+           |
                      |                             |                                            |
  +-------------------v---------------------------+ |  +-----------------------------------------+
  |                                               | |  |                                         |
  |                                               | |  |                                         |
  | MishkaInstaller.Installer.DepChangesProtector +-+  | MishkaInstaller.Installer.Live.DepGetter|
  |                                               |    |                                         |
  |                                               |    |                                         |
  +---------------------+-------------------------+    +-----------------------------------------+
                        |
                        |
    +-------------------v-----------------------+
    |                                           |
    | MishkaInstaller.Installer.RunTimeSourcing |
    |                                           |
    +-------------------------------------------+

  ```

  As you can see in the graph above, most of the requests, except the update request, pass through the path of the
  `MishkaInstaller.DepCompileJob` module and call some functions of the `MishkaInstaller.Installer.DepHandler` module.
  After completing the operation process, this module finally serializes the queued requests and broadcasts the output by means of `Pubsub`.

  - **Warning**: Direct use of this module causes conflict in long operations and causes you to receive an error,
  or the system is completely down.
  - **Warning**: The update operation is connected to the worker of the `MishkaInstaller.DepUpdateJob` module.
  - **Warning**: this section should be limited to the super admin user because it is directly related to the core of the system.
  - **Warning**: User should always be notified to get backup.
  - **Warning**: Do not send timeout request to Genserver of this module.
  - **Warning**: This module must be supervised in the `Application.ex` file and loaded at runtime.
  - **Warning**: this module has a direct relationship with the `extension.json` file, so it checks this file every few seconds and
  fixes it if it is not created or has a problem.
  - **Warning**: If you put `Pubsub` in your configuration settings and the value is not nil, this module will automatically send
  a timeout several times until your Pubsub process goes live.
  - **Warning**: at the time of starting Genserver, this module also starts `MishkaInstaller.DepUpdateJob.ets/0` runtime database.
  - **Warning**: All possible errors are stored in the database introduced in the configuration, and you can access it with the
  functions of the `MishkaInstaller.Activity` module.
  """
  use GenServer, restart: :permanent
  require Logger
  @re_check_json_time 10_000
  @module "dep_changes_protector"
  alias MishkaInstaller.Installer.DepHandler
  alias MishkaInstaller.Dependency

  @doc false
  @spec start_link(list()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc false
  @spec push(map(), String.t() | atom()) :: map()
  def push(app, status) do
    GenServer.call(__MODULE__, {:push, app: app, status: status})
  end

  @doc false
  @spec get(String.t()) :: map()
  def get(app) do
    GenServer.call(__MODULE__, {:get, app})
  end

  @spec get :: map()
  def get() do
    GenServer.call(__MODULE__, :get)
  end

  @doc false
  @spec pop(String.t()) :: map()
  def pop(app) do
    GenServer.call(__MODULE__, {:pop, app})
  end

  @doc false
  @spec clean :: :ok
  def clean() do
    GenServer.cast(__MODULE__, :clean)
  end

  @doc """
  This function is actually an action function and aggregator.
  You call this `GenServer.cast` function with three inputs `{:deps, app, type}`, which executes with a very small timeout.
  Warning: It is highly recommended not to call this function directly and use the worker (`MishkaInstaller.DepCompileJob`)
  to compile. Finally, this function calls the `MishkaInstaller.Installer.RunTimeSourcing.do_deps_compile/2` function with the help of
  `Task.Supervisor.async_nolink/2`.
  It is worth mentioning that you can view and monitor the output by subscribing to this module.

  ## Examples
  ```elixir
  MishkaInstaller.Installer.DepChangesProtector.deps(app_name, output_type)
  ```
  """
  @spec deps(String.t(), atom()) :: :ok
  def deps(app, type \\ :port) do
    GenServer.cast(__MODULE__, {:deps, app, type})
  end

  @impl true
  def init(_state) do
    Logger.info("OTP Dependencies changes protector server was started")
    # Start update ets
    MishkaInstaller.DepUpdateJob.ets()
    {:ok, %{data: nil, ref: nil}, {:continue, :check_json}}
  end

  @impl true
  def handle_continue(:check_json, state) do
    check_custom_pubsub_loaded(state)
  end

  @impl true
  def handle_continue(:add_extensions, state) do
    add_extensions_when_server_reset(state)
  end

  @impl true
  def handle_info(:check_json, state) do
    if Mix.env() not in [:dev, :test],
      do: Logger.info("OTP Dependencies changes protector Cache server was valued by JSON.")

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
    project_path = MishkaInstaller.get_config(:project_path)

    case app_res do
      {:ok, :application_ensure} ->
        [
          Path.join(project_path, ["deployment/extensions/", "#{app_name}", "/_build"]),
          Path.join(project_path, ["deployment/extensions/", "#{app_name}", "/deps"])
        ]
        |> Enum.map(&File.rm_rf(&1))

        notify_subscribers({:ok, app_res, app_name})

      {:error, do_runtime, app, operation: operation, output: output} ->
        notify_subscribers({:error, app_res, "#{app}"})

        MishkaInstaller.dependency_activity(
          %{state: [{:error, do_runtime, "#{app}", operation: operation, output: output}]},
          "high"
        )

      {:error, do_runtime, ensure, output} ->
        notify_subscribers({:error, app_res, app_name})

        MishkaInstaller.dependency_activity(
          %{state: [{:error, do_runtime, app_name, operation: ensure, output: output}]},
          "high"
        )
    end

    Oban.resume_queue(queue: :compile_events)
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, answer}, %{ref: ref} = state) do
    # The task completed successfully
    {:noreply,
     Map.merge(state, %{data: update_dependency_type(answer, state) || state, ref: nil, app: nil})}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _status}, state) do
    {:noreply, %{state | ref: nil}}
  end

  @impl true
  def handle_info({:do_compile, app, type}, state) do
    task =
      Task.Supervisor.async_nolink(DepChangesProtectorTask, fn ->
        MishkaInstaller.Installer.RunTimeSourcing.do_deps_compile(app, type)
      end)

    {:noreply, Map.merge(state, %{ref: task.ref, app: app})}
  end

  @impl true
  def handle_info(:start_oban, state) do
    Logger.info("We sent a request to start oban")
    MishkaInstaller.start_oban_in_runtime()
    {:noreply, state}
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
      case Enum.find(state.data, &(&1.app == app)) do
        nil ->
          new_app = %{app: app, status: status, time: DateTime.utc_now()}
          {:reply, new_app, Map.merge(state, %{data: state.data ++ [new_app]})}

        _ ->
          {:reply, {:duplicate, app}, state}
      end

    new_state
  end

  @impl true
  def handle_call({:get, app}, _from, state) do
    {:reply, Enum.find(state.data, &(&1.app == app)), state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:pop, app}, _from, state) do
    new_state = Enum.reject(state.data, &(&1.app == app))
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

  @doc """
  This function checks if any process is running or not.
  if `true` means no job is being done, if `false` means there is a job is being done.

  ## Examples
  ```elixir
  MishkaInstaller.Installer.DepChangesProtector.is_dependency_compiling?()
  ```
  """
  @spec is_dependency_compiling? :: boolean
  def is_dependency_compiling?(), do: is_nil(get().ref)

  # For now, we decided to remove and re-create JSON file to prevent user not to delete or wrong edit manually
  defp json_check_and_create() do
    File.rm_rf(DepHandler.extensions_json_path())
    {:ok, :check_or_create_deps_json, json} = DepHandler.check_or_create_deps_json()
    {:ok, :read_dep_json, data} = DepHandler.read_dep_json(json)

    Enum.filter(data, &(&1["dependency_type"] == "force_update"))
    |> Enum.map(&%{app: &1["app"], status: &1["dependency_type"], time: DateTime.utc_now()})
  rescue
    _e -> []
  end

  defp update_dependency_type(answer, state, dependency_type \\ "none") do
    with {:ok, :do_deps_compile, app_name} <- answer,
         {:ok, :change_dependency_type_with_app, _repo_data} <-
           Dependency.change_dependency_type_with_app(app_name, dependency_type) do
      json_check_and_create()

      # TODO: it should be changed to outofproject
      with {:ok, :compare_installed_deps_with_app_file, apps_list} <-
             DepHandler.compare_installed_deps_with_app_file("#{app_name}") do
        Task.Supervisor.async_nolink(DepChangesProtectorTask, fn ->
          MishkaInstaller.Installer.RunTimeSourcing.do_runtime(
            String.to_atom(state.app),
            :uninstall
          )

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
        MishkaInstaller.dependency_activity(
          %{state: [answer], action: "edit", error: repo_error},
          "high"
        )
    end
  end

  defp check_custom_pubsub_loaded(state) do
    custom_pubsub = MishkaInstaller.get_config(:pubsub)

    cond do
      !is_nil(custom_pubsub) && is_nil(Process.whereis(custom_pubsub)) ->
        {:noreply, state, 100}

      true ->
        Process.send_after(self(), :check_json, @re_check_json_time)
        Process.send_after(self(), :start_oban, @re_check_json_time)
        MishkaInstaller.Dependency.subscribe()
        {:noreply, state, {:continue, :add_extensions}}
    end
  end

  @doc """
  This function helps the programmer to join the channel of this module(`MishkaInstaller.Installer.DepChangesProtector`)
  and receive the output as a broadcast in the form of `{status, :dep_changes_protector, answer, app}`.
  It uses `Phoenix.PubSub.subscribe/2`.

  ## Examples
  ```elixir
  # Subscribe to `MishkaInstaller.Installer.DepChangesProtector` module
  MishkaInstaller.Installer.DepChangesProtector.subscribe()

  # Getting the answer as Pubsub for examples in LiveView
  @impl Phoenix.LiveView
  def handle_info({status, :dep_changes_protector, answer, app}, socket) do
    {:noreply, socket}
  end
  ```
  """
  @spec subscribe :: :ok | {:error, {:already_registered, pid}}
  def subscribe do
    Phoenix.PubSub.subscribe(
      MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub,
      @module
    )
  end

  @doc false
  @spec notify_subscribers({atom(), any, String.t() | atom()}) :: :ok | {:error, any}
  defp notify_subscribers({status, answer, app}) do
    Phoenix.PubSub.broadcast(
      MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub,
      @module,
      {status, String.to_atom(@module), answer, app}
    )
  end

  defp add_extensions_when_server_reset(state) do
    Logger.warn("Try to re-add installed extensions")
    # TODO: add status for each app is active or stopped, not load them in nex version
    # TODO: try to add them and check which app does not exist in bin
    if Mix.env() != :test do
      MishkaInstaller.Dependency.dependencies()
      |> Enum.map(fn item ->
        MishkaInstaller.Installer.RunTimeSourcing.do_runtime(item.app, :add)
        |> case do
          {:error, :prepend_compiled_apps, :bad_directory, list} -> IO.inspect(list, label: "This app does not exist in bin/_build")
          {:ok, :application_ensure} -> Logger.info("All installed extensions re-added")
          output -> Logger.emergency("We have problem to add all extensions, #{inspect(output)}")
        end
      end)
    end
    {:noreply, state}
  end
end
