defmodule MishkaInstaller.Event.Hook do
  alias MishkaInstaller.Event.{Event, ModuleStateCompiler}

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      use GenServer, restart: :transient
      alias MishkaInstaller.Event.{Event, Hook}

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
      end

      def stop() do
      end

      def unregister() do
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

        {:ok, new_state}
      end
    end
  end

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @spec call(String.t(), any(), any()) :: any()
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
end
