defmodule MishkaInstaller.Event.Hook do
  alias MishkaInstaller.Event.{Event, ModuleStateCompiler}

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      use GenServer, restart: :transient
      alias MishkaInstaller.Event.{Event, Hook, EventHandler}
      alias MishkaInstaller.Event.ModuleStateCompiler, as: MSE

      # Based on https://elixirforum.com/t/59168/5
      @app_config Mix.Project.config()
      @plugin_event Keyword.get(opts, :event)
      @initial Keyword.get(opts, :initial, %{})
      @plugin_name __MODULE__
      @wait_for_tables 6000
      @after_compile __MODULE__
      @checking Keyword.get(opts, :checking, 1000)

      def config(),
        do: Keyword.merge(@app_config, __plugin__: @plugin_name, __event__: @plugin_event)

      def config(key), do: Keyword.get(config(), key)

      def register() do
        Event.register(config(:__plugin__), config(:__event__), @initial)
      end

      def start() do
        Event.start(:name, config(:__plugin__))
      end

      def restart() do
        Event.restart(:name, config(:__plugin__))
      end

      def stop() do
        Event.stop(:name, config(:__plugin__))
      end

      def unregister() do
        Event.unregister(:name, config(:__plugin__))
      end

      def get() do
        GenServer.call(__MODULE__, :get)
      end

      defoverridable register: 0,
                     start: 0,
                     restart: 0,
                     stop: 0,
                     unregister: 0,
                     get: 0

      def __after_compile__(_env, _bytecode) do
        unless Module.defines?(__MODULE__, {:call, 1}) do
          raise "#{inspect(__MODULE__)} should have call/1 function."
        end

        if is_nil(config(:__event__)) do
          raise "#{inspect(__MODULE__)} should be dedicated to an event."
        end
      end

      def start_link(args \\ []) do
        GenServer.start_link(@plugin_name, args, name: @plugin_name)
      end

      @impl true
      def init(state) do
        MishkaInstaller.subscribe("event")

        new_state =
          Keyword.merge(state, name: __MODULE__, event: @plugin_event, status: :starting)

        {:ok, new_state, {:continue, :start_plugin}}
      end

      @impl true
      def handle_continue(:start_plugin, state) do
        MnesiaAssistant.Table.wait_for_tables([Event], @wait_for_tables)

        new_state =
          if :persistent_term.get(:event_status, nil) == "ready" do
            Hook.register_start_helper(__MODULE__, state)
          else
            Process.send_after(__MODULE__, :register_start_again, 1000)
            state
          end

        Process.send_after(__MODULE__, :status, 1000)
        {:noreply, new_state}
      end

      @impl true
      def handle_call(:get, _from, state) do
        {:reply, state, state}
      end

      @impl true
      def handle_call(_reason, _from, state) do
        {:reply, state, state}
      end

      @impl true
      def handle_info(:start_again, state) do
        event = Keyword.get(state, :event)
        db_plg = Event.get(:name, Keyword.get(state, :name))
        module = MSE.module_event_name(event)

        new_state =
          if MSE.safe_initialize?(event) and module.is_initialized?(db_plg) do
            Keyword.merge(state, status: db_plg.status, depends: db_plg.depends)
          else
            Hook.start_helper(__MODULE__, state, db_plg)
          end

        {:noreply, new_state}
      end

      def handle_info(%{status: status, data: data}, state)
          when status in [:start, :stop, :unregister] do
        event = Keyword.get(state, :event)
        depends = Keyword.get(state, :depends, [])
        # We need some state, it will be saved again or not, it should not be loaded if
        # |__ it is restored
        event_status = :persistent_term.get(:event_status, nil)

        new_state =
          with true <- event_status == "ready",
               true <- event == Map.get(data, :event),
               true <- Map.get(data, :name) in depends,
               :ok <- Event.allowed_events?(depends),
               {:ok, struct} <- Event.write(:name, @plugin_name, %{status: :restarted}),
               _ok <- EventHandler.do_compile(struct.event, :re_event) do
            Keyword.merge(state, status: :restarted)
          else
            _ -> state
          end

        {:noreply, new_state}
      end

      def handle_info(%{status: :re_event, data: _data}, state) do
        new_state =
          case Event.get(:name, state[:name]) do
            nil -> state
            data -> Keyword.merge(state, status: data.status)
          end

        {:noreply, state}
      end

      def handle_info(:status, state) do
        Process.send_after(__MODULE__, :status, @checking)

        new_state =
          with "ready" <- :persistent_term.get(:event_status, nil),
               {:module, module} <- Code.ensure_loaded(MSE.module_event_name(@plugin_event)),
               data when not is_nil(data) <-
                 Enum.find(module.initialize().plugins, &(&1.name == @plugin_name)) do
            case Event.get(:name, @plugin_name) do
              nil -> state
              plugin -> Keyword.merge(state, status: plugin.status)
            end
          else
            _ -> state
          end

        {:noreply, new_state}
      end

      @impl true
      def handle_info(_reason, state) do
        {:noreply, state}
      end
    end
  end

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @spec call(String.t(), any(), keyword()) :: any()
  def call(event, data, args \\ []) do
    module = ModuleStateCompiler.module_event_name(event)

    if function_exported?(module, :call, 2) do
      module.call(data, args)
    else
      {:error, :undefined_function_error}
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  @spec start_helper(module(), keyword(), any()) :: keyword()
  @doc false
  def start_helper(module, state, reg_db_plg) do
    case module.start() do
      {:ok, st_db_plg} ->
        Keyword.merge(state, status: st_db_plg.status, depends: st_db_plg.depends)

      {:error, [%{field: :event, action: :compile}]} ->
        Process.send_after(module, :start_again, 1000)
        Keyword.merge(state, status: :held, depends: reg_db_plg.depends)

      _error ->
        Keyword.merge(state, status: reg_db_plg.status, depends: reg_db_plg.depends)
    end
  end

  @doc false
  @spec register_start_helper(module(), keyword()) :: keyword()
  def register_start_helper(module, state) do
    case module.register() do
      {:ok, reg_db_plg} ->
        start_helper(module, state, reg_db_plg)

      _error ->
        state
    end
  end
end
