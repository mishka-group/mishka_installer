defmodule MishkaInstaller.PluginState do
  @moduledoc """
  This module served as the first layer in the domain of plugin state management in earlier versions;
  however, following optimization using ETS, it is now regarded as the main structure in the second layer.

  If a developer chooses to construct a custom plugin by using the `use MishkaInstaller.Hook` directive,
  then the developer actually implements this module as the first layer to register a plugin and the second layer as a supervisor.
  The scope of a plugin's state management is not restricted to the automatically specified duties performed by the `MishkaInstaller`;
  for instance, it provides developers with a temporary state and offers them the freedom to act in accordance with whatever method they choose.


  ### Each plugin should have these parameters

  ```elixir
    defstruct [:name, :event, priority: 1, status: :started, depend_type: :soft, depends: [], extra: [], parent_pid: nil]
  ```


  ### Module communication process of MishkaInstaller.PluginState

  ```
         +------------------------------------------------+
         |                                                |
         |                                                |
  +------+  MishkaInstaller.PluginStateDynamicSupervisor  |
  |      |                                                |
  |      |                                                |
  |      +--------------------------------------+----^----+
  |                                             |    |
  |                                             |    |
  |                                             |    |
  |      +------------------------+             |    |
  |      |                        |             |    |
  +------>  PluginStateRegistry   |             |    |
         |                        |             |    |
         +--------^---------------+             |    |
                  |                             |    |
                  |                             |    |
                  |                             |    |
                  |                             |    |
                  |        +--------------------v----+-----+
                  |        |                               |
                  |        |  MishkaInstaller.PluginState  |
                  +--------+                               |
                           +--------------------+--------^-+
                                                |        |
                                                |        |
                                                |        |
                                                |        |
            +----------------------------+      |        |
            |                            |      |        |
            | MishkaInstaller.PluginETS  <------+        |
            |                            |               |
            +----------------------------+               |
                                                         |
                                                         |
                                                         |
                                    +--------------------+-+
                                    |                      |
                      +-------------+ MishkaInstaller.Hook |
                      |             |                      |
                      |             +----------------------+
                      |
                      |
            +---------v----------------------+
            |                                |
            |     Behaviour References       |
            |                                |
            +--------------------------------+
  ```
  """

  use GenServer
  require Logger
  alias MishkaInstaller.PluginStateDynamicSupervisor, as: PSupervisor
  alias MishkaInstaller.Plugin
  alias __MODULE__

  defstruct [
    :name,
    :event,
    :extension,
    priority: 1,
    status: :started,
    depend_type: :soft,
    depends: [],
    extra: [],
    parent_pid: nil
  ]

  @typedoc "This type can be used when you want to introduce the parameters of a plugin"
  @type params() :: map()
  @typedoc "This type can be used when you want to introduce an ID of a plugin"
  @type id() :: String.t()
  @typedoc "This type can be used when you want to introduce an plugin name"
  @type module_name() :: String.t()
  @typedoc "This type can be used when you want to introduce an event name"
  @type event_name() :: String.t()
  @typedoc "This type can be used when you want to introduce an event owner extension"
  @type extension() :: String.t()
  @typedoc "This type can be used when you want to introduce an event"
  @type plugin() :: %PluginState{
          name: module_name(),
          event: event_name(),
          extension: module(),
          priority: integer(),
          status: :started | :stopped | :restarted,
          depend_type: :soft | :hard,
          parent_pid: any(),
          depends: list(String.t()),
          extra: list(map())
        }
  @typedoc "This type can be used when you want to introduce an event"
  @type t :: plugin()

  @doc """
  You should in no way use this function in its direct form. The supervisor coverage needs to run before using this function since
  it will establish a state for your plugin and save its PID in the registry.
  Make use of the function named `MishkaInstaller.PluginStateDynamicSupervisor.start_job/1`.
  """
  def start_link(args) do
    {id, type, parent_pid} =
      {Map.get(args, :id), Map.get(args, :type), Map.get(args, :parent_pid)}

    GenServer.start_link(__MODULE__, default(id, type, parent_pid), name: via(id, type))
  end

  @doc false
  def child_spec(process_name) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [process_name]},
      restart: :transient,
      max_restarts: 4
    }
  end

  defp default(plugin_name, event, parent_pid) do
    %PluginState{name: plugin_name, event: event, parent_pid: parent_pid}
  end

  @doc """
  This function helps you to create the state of a plugin. Please see `t:plugin/0` type documents. This function does not wait for a response.

  ## Examples
  ```elixir
  plugin =
    %MishkaInstaller.PluginState{
      name: "unnested_plugin_five",
      event: "nested_event_one",
      depend_type: :hard,
      depends: ["unnested_plugin_four"]
    }
  MishkaInstaller.PluginState.push(plugin)
  ```
  """
  @spec push(MishkaInstaller.PluginState.t()) :: :ok | {:error, :push, any}
  def push(%PluginState{} = element) do
    case PSupervisor.start_job(%{
           id: element.name,
           type: element.event,
           parent_pid: element.parent_pid
         }) do
      {:ok, status, pid} -> GenServer.cast(pid, {:push, status, element})
      {:error, result} -> {:error, :push, result}
    end
  end

  @doc """
  This function does the same thing as the `push/1` function, except that it waits for a response.
  """
  @spec push_call(MishkaInstaller.PluginState.t()) :: :ok | {:error, :push, any}
  def push_call(%PluginState{} = element) do
    case PSupervisor.start_job(%{
           id: element.name,
           type: element.event,
           parent_pid: element.parent_pid
         }) do
      {:ok, status, pid} ->
        if Mix.env() == :test, do: Logger.warn("Plugin State of #{element.name} is being pushed")
        GenServer.call(pid, {:push, status, element})

      {:error, result} ->
        {:error, :push, result}
    end
  end

  @doc """
  It gets a plugin information from the state.

  ## Examples
  ```elixir
  MishkaInstaller.PluginState.get(module: "PluginTest")
  ```
  """
  @spec get([{:module, module_name()}]) :: plugin() | {:error, :get, :not_found}
  def get(module: module_name) do
    case PSupervisor.get_plugin_pid(module_name) do
      {:ok, :get_plugin_pid, pid} -> GenServer.call(pid, {:pop, :module})
      {:error, :get_plugin_pid} -> {:error, :get, :not_found}
    end
  end

  @doc """
  This function gets all information of plugins which are under a specific event.

  ## Examples
  ```elixir
  MishkaInstaller.PluginState.get_all(event: "event_test")
  ```
  """
  def get_all(event: event_name) do
    PSupervisor.running_imports(event_name) |> Enum.map(&get(module: &1.id))
  end

  @doc """
  This function gets all information of plugins which are pushed on the state.

  ## Examples
  ```elixir
  MishkaInstaller.PluginState.get_all()
  ```
  """
  def get_all() do
    PSupervisor.running_imports() |> Enum.map(&get(module: &1.id))
  end

  @doc """
  Delete a plugin or plugins based on a specific event from the state.

  ## Examples
  ```elixir
  MishkaInstaller.PluginState.delete(module: "PluginTest")
  # or
  MishkaInstaller.PluginState.delete(event: "EventTest")
  ```
  """
  def delete(module: module_name) do
    case PSupervisor.get_plugin_pid(module_name) do
      {:ok, :get_plugin_pid, pid} ->
        GenServer.cast(pid, {:delete, :module})
        {:ok, :delete}

      {:error, :get_plugin_pid} ->
        {:error, :delete, :not_found}
    end
  end

  def delete(event: event_name) do
    PSupervisor.running_imports(event_name) |> Enum.map(&delete(module: &1.id))
  end

  @doc """
  Terminate a PID from the supervisor directly.

  ## Examples
  ```elixir
  MishkaInstaller.PluginState.delete_child(module: "PluginTest")
  ```
  """
  def delete_child(module: module_name) do
    case PSupervisor.get_plugin_pid(module_name) do
      {:ok, :get_plugin_pid, pid} -> DynamicSupervisor.terminate_child(PluginStateOtpRunner, pid)
      {:error, :get_plugin_pid} -> {:error, :delete, :not_found}
    end
  end

  @doc """
  Terminate all PIDs of the plugin state from the supervisor directly.

  ## Examples
  ```elixir
  MishkaInstaller.PluginState.terminate_all_pids()
  ```
  """
  def terminate_all_pids() do
    Enum.map(PSupervisor.running_imports(), fn item ->
      GenServer.cast(item.pid, {:delete, :module})
    end)
  end

  @doc """
  Stop a plugin state.

  ## Examples
  ```elixir
  MishkaInstaller.PluginState.stop(module: PluginTest)
  # or
  MishkaInstaller.PluginState.stop(event: "event_test")
  ```
  """
  def stop(module: module_name) do
    case PSupervisor.get_plugin_pid(module_name) do
      {:ok, :get_plugin_pid, pid} ->
        GenServer.cast(pid, {:stop, :module})
        {:ok, :stop}

      {:error, :get_plugin_pid} ->
        {:error, :stop, :not_found}
    end
  end

  def stop(event: event_name) do
    PSupervisor.running_imports(event_name) |> Enum.map(&stop(module: &1.id))
  end

  # Callbacks
  @impl true
  def init(%PluginState{} = state) do
    if Mix.env() == :test, do: MishkaInstaller.Database.Helper.get_parent_pid(state)

    Logger.info(
      "#{Map.get(state, :name)} from #{Map.get(state, :event)} event of Plugins manager system was started"
    )

    {:ok, state, {:continue, {:sync_with_database, :take}}}
  end

  @impl true
  def handle_call({:pop, :module}, _from, %PluginState{} = state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:push, _status, %PluginState{} = element}, _from, %PluginState{} = _state) do
    element
    |> Map.from_struct()
    |> Plugin.add_or_edit_by_name()

    {:reply, element, element}
  end

  @impl true
  def handle_cast({:push, status, %PluginState{} = element}, _state) do
    {:noreply, element, {:continue, {:sync_with_database, status}}}
  end

  @impl true
  def handle_cast({:stop, :module}, %PluginState{} = state) do
    new_state = Map.merge(state, %{status: :stopped})
    {:noreply, new_state, {:continue, {:sync_with_database, :edit}}}
  end

  @impl true
  def handle_cast({:delete, :module}, %PluginState{} = state) do
    MishkaInstaller.plugin_activity("destroy", state, "high", "report")
    {:stop, :normal, state}
  end

  @impl true
  def handle_continue({:sync_with_database, _status}, %PluginState{} = state) do
    state
    |> Map.from_struct()
    |> Plugin.add_or_edit_by_name()
    |> check_output(state)

    {:noreply, state}
  end

  @impl true
  def handle_continue({:sync_with_database, :take}, %PluginState{} = state) do
    state =
      case Plugin.show_by_name("#{state.name}") do
        {:ok, :get_record_by_field, _error_atom, record_info} ->
          struct(__MODULE__, Map.from_struct(record_info))

        {:error, _result, _error_atom} ->
          state
      end

    {:noreply, state}
  end

  if Mix.env() in [:test, :dev] do
    @impl true
    def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
      # log that this happened, etc. Don't use Repo!
      {:stop, :normal, state}
    end
  end

  @impl true
  def terminate(reason, %PluginState{} = state) do
    MishkaInstaller.plugin_activity("read", state, "high", "throw")

    if reason != :normal do
      Task.Supervisor.start_child(PluginEtsTask, fn ->
        MishkaInstaller.PluginETS.sync_with_database()
      end)

      Logger.warn(
        "#{Map.get(state, :name)} from #{Map.get(state, :event)} event of Plugins manager was Terminated,
        Reason of Terminate #{inspect(reason)}"
      )
    end
  end

  defp via(id, value) do
    {:via, Registry, {PluginStateRegistry, id, value}}
  end

  defp check_output({:error, status, _, _} = _output, %PluginState{} = state) do
    MishkaInstaller.plugin_activity("#{status}", state, "high", "error")
  end

  defp check_output({:ok, status, _, _} = _output, %PluginState{} = state) do
    action =
      cond do
        status == :add -> "add"
        state.status == :stopped -> "delete"
        true -> "edit"
      end

    MishkaInstaller.plugin_activity(action, state, "high")
  end
end
