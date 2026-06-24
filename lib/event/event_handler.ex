defmodule MishkaInstaller.Event.EventHandler do
  @moduledoc """
  Serialises (re)compilation of the per-event plugin modules.

  Compile requests are queued and run one at a time so the dynamically generated event modules are
  never created and destroyed concurrently.

  The compiled module is per node (in-memory, not in Mnesia). On boot each node builds its own copy
  from the replicated table; at runtime a local (re)compile is broadcast cluster-wide so every node
  rebuilds the affected event from the replicated table — keeping `Hook.call/3` consistent across
  the cluster.

  ## Telemetry

  - `[:mishka_installer, :event, :compile]` — emitted after an event module is (re)built.
    Metadata: `:event`, `:result` (`:ok` | `:error`).
  - `[:mishka_installer, :event, :synchronized]` — emitted once all events have started after the
    Mnesia store is ready. Metadata: `:node`.
  """
  use GenServer
  require Logger
  alias MishkaInstaller.Event.{Event, ModuleStateCompiler}
  alias MishkaInstaller.QueueAssistant

  @telemetry [:mishka_installer, :event]

  ################################################################################
  ######################## (▰˘◡˘▰) Init data (▰˘◡˘▰) #######################
  ################################################################################
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  @spec init(keyword()) :: {:ok, keyword()}
  def init(state \\ []) do
    Logger.metadata(domain: [:mishka_installer, :event])
    MishkaInstaller.subscribe("mnesia")
    MishkaInstaller.subscribe("event")
    {:ok, Keyword.merge(state, running: [], queues: QueueAssistant.new())}
  end

  ####################################################################################
  ######################## (▰˘◡˘▰) Public APIs (▰˘◡˘▰) #########################
  ####################################################################################
  @spec do_compile(String.t(), atom(), boolean()) :: :ok
  def do_compile(event, status, queue \\ true) do
    if queue do
      GenServer.cast(__MODULE__, {:do_compile, event, status})
    else
      # Synchronous compile, but still run INSIDE the GenServer (via call) so it is serialised with
      # every other compile and never races a queued one. The caller blocks until the module is built.
      GenServer.call(__MODULE__, {:do_compile, event, status})
    end
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

  def handle_call({:do_compile, event, status}, _from, state) do
    MishkaInstaller.broadcast("event", status, %{})

    result =
      if perform(event) do
        broadcast_recompile(event)
        :ok
      else
        {:error,
         [
           %{
             message: "An error occurred in the compile of an event.",
             field: :global,
             action: status
           }
         ]}
      end

    {:reply, result, state}
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
        event = List.first(running)

        if perform(event),
          do: broadcast_recompile(event),
          else: Logger.error("[mishka_installer.event] compile error for event #{inspect(event)}")

        send(self(), :run_queues)
        Keyword.merge(state, running: [])
      else
        state
      end

    {:noreply, new_state}
  end

  def handle_info(%{status: :synchronized, channel: "mnesia"}, state) do
    new_state =
      if :persistent_term.get(:compile_status, nil) == "ready",
        do: synchronized_start(state),
        else: state

    {:noreply, new_state}
  end

  def handle_info(%{status: :compile_synchronized, channel: "mnesia"}, state) do
    {:noreply, synchronized_start(state)}
  end

  def handle_info(
        %{status: :cluster_recompile, channel: "event", data: %{event: event, origin: origin}},
        state
      )
      when origin != node() do
    perform(event)
    {:noreply, state}
  end

  # Membership changed (a node joined/reconnected): rebuild any event module that drifted while a
  # node was away. Each rebuild is gated by `is_changed?`, so unchanged events cost nothing.
  def handle_info(%{status: :cluster_changed, channel: "mnesia"}, state) do
    if Keyword.get(state, :status) == :synchronized do
      case Event.group_events() do
        {:ok, events} -> Enum.each(events, &do_compile(&1, :reconcile))
        _ -> :ok
      end
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
  defp synchronized_start(state) do
    case Event.start() do
      {:ok, _sorted_events} ->
        :persistent_term.put(:event_status, "ready")
        Logger.info("[mishka_installer.event] plugins synchronized")
        MishkaInstaller.broadcast("mnesia", :event_status, "ready")
        telemetry(:synchronized, %{node: node()})
        Keyword.merge(state, status: :synchronized)

      _ ->
        state
    end
  end

  defp perform(event) do
    sorted_plugins =
      Event.get(:event, event)
      |> Enum.filter(fn pl ->
        Event.plugin_status(pl.status) == :ok and Event.allowed_events?(pl.depends) == :ok
      end)
      |> Event.dependency_order()

    inaccessible = for pl <- sorted_plugins, not plugin_callable?(pl.name), do: pl.name

    module = ModuleStateCompiler.module_event_name(event)
    recompile(compiled?(module), module, sorted_plugins, inaccessible, event)

    telemetry(:compile, %{event: event, result: :ok})
    true
  rescue
    error ->
      Logger.error(
        "[mishka_installer.event] compile failed for event #{inspect(event)}: #{inspect(error)}"
      )

      telemetry(:compile, %{event: event, result: :error})
      false
  end

  # Not compiled yet: build it.
  defp recompile(false, _module, sorted_plugins, inaccessible, event),
    do: purge_create(sorted_plugins, inaccessible, event)

  # Already compiled: rebuild only when the plugin set or the accessibility mode changed.
  defp recompile(true, module, sorted_plugins, inaccessible, event) do
    desired_mode = if inaccessible == [], do: :ok, else: :error

    if module.is_changed?(sorted_plugins) or safe_mode(module) != desired_mode,
      do: purge_create(sorted_plugins, inaccessible, event),
      else: :ok
  end

  defp compiled?(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :is_changed?, 1)

  defp plugin_callable?(name),
    do:
      Code.ensure_loaded?(name) and
        (function_exported?(name, :call, 1) or function_exported?(name, :call, 2))

  defp safe_mode(module),
    do: if(function_exported?(module, :mode, 0), do: module.mode(), else: :ok)

  defp purge_create(sorted_plugins, inaccessible, event) do
    :ok = ModuleStateCompiler.purge_create(sorted_plugins, event, inaccessible)
    :ok = MishkaInstaller.broadcast("event", :purge_create, event)
  end

  defp broadcast_recompile(event) do
    MishkaInstaller.broadcast("event", :cluster_recompile, %{event: event, origin: node()})
  end

  defp telemetry(name, metadata) do
    :telemetry.execute(@telemetry ++ [name], %{system_time: System.system_time()}, metadata)
  end
end
