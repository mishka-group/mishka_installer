defmodule MishkaInstaller.Event.EventHandler do
  @moduledoc false
  use GenServer
  require Logger
  alias MishkaInstaller.Event.{Event, ModuleStateCompiler}
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
    MishkaInstaller.subscribe("mnesia")
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
      MishkaInstaller.broadcast("event", status, %{})

      case perform(event) do
        false ->
          message = "An error occurred in the compile of an event."
          {:error, [%{message: message, field: :global, action: status}]}

        true ->
          :ok
      end
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
        output = perform(List.first(running))

        if !output do
          Logger.error(
            "Identifier: #{inspect(__MODULE__)} ::: Compiling error! ::: Source: #{event}"
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
    new_state =
      if :persistent_term.get(:compile_status, nil) == "ready",
        do: synchronized_start(state),
        else: state

    {:noreply, new_state}
  end

  def handle_info(%{status: :compile_synchronized, channel: "mnesia"}, state) do
    {:noreply, synchronized_start(state)}
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
        Logger.debug("Identifier: #{inspect(__MODULE__)} ::: Plugins are Synchronized...")
        MishkaInstaller.broadcast("mnesia", :event_status, "ready")
        Keyword.merge(state, status: :synchronized)

      _ ->
        state
    end
  end

  defp perform(event) do
    plugins = Event.get(:event, event)

    sorted_plugins =
      Enum.reduce(plugins, [], fn pl_item, acc ->
        with :ok <- Event.plugin_status(pl_item.status),
             :ok <- Event.allowed_events?(pl_item.depends) do
          acc ++ [pl_item]
        else
          _ -> acc
        end
      end)
      |> Enum.sort_by(&{&1.priority, &1.name})

    module = ModuleStateCompiler.module_event_name(event)

    if Code.ensure_loaded?(module) and function_exported?(module, :is_changed?, 1) and
         module.is_changed?(sorted_plugins) do
      purge_create(sorted_plugins, event)
    end

    if !Code.ensure_loaded?(module) and !function_exported?(module, :is_changed?, 1) do
      purge_create(sorted_plugins, event)
    end

    true
  rescue
    _ ->
      Logger.error("Identifier: #{inspect(__MODULE__)} ::: Compiling error! ::: Source: #{event}")
      false
  end

  defp purge_create(sorted_plugins, event) do
    :ok = ModuleStateCompiler.purge_create(sorted_plugins, event)
    :ok = MishkaInstaller.broadcast("event", :purge_create, event)
  end
end
