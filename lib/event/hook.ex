defmodule MishkaInstaller.Event.Hook do
  @moduledoc """
  The `MishkaInstaller.Event.Hook` module provides a set of functionalities to manage event hooks
  within the Mishka Installer system.

  It leverages `GenServer` to handle asynchronous event-driven operations and offers a set of
  macros and functions for registering, starting, stopping, and managing hooks dynamically.

  In addition to being one of the most significant modules of the MishkaInstaller library,
  the Hook module gives you the ability to make the library as a whole,
  as well as the projects that make use of this library, more modular.

  It is essential to comprehend that you may treat any action performed independently
  as an event and register an unlimited number of plugins for that event.

  You can do this by considering that action to be done separately.
  Each plugin has the potential to have its own individual inputs and outputs,
  and depending on the architecture of the area that you want to use Hook in,
  you may even be able to change the output and send it to other plugins.

  Throughout all of the many parts that have been built for this module,
  it has been attempted to have a flexible approach to dealing with errors
  and to provide the programmer with a wide variety of options.

  With the additional functions at her disposal, the programmer can actually create a
  gateway in their projects, where the data flow must pass through several gates,
  whether it changes or remains unchanged, and a series of operations are performed.

  For illustration's sake, let's suppose you want the registration system to allow users
  to sign up for social networks on Twitter and Google.

  When you use this library, it is conceivable that you can quickly display HTML
  or even operate in the background before registering after registering.

  This is a significant improvement over the standard practice,
  in which you are required to modify the primary codes of your project. Create a separate plugin.

  It is interesting to notice that these facilities are quite basic and convenient for the admin user.

  If this opportunity is provided, the management can manage its own plugins in different ways
  if it has a dashboard.

  It is crucial to highlight that each plugin is its own `GenServer`; in addition,
  it is dynamically supervised, and the information is stored in the database as well as in Mnesia.

  Furthermore, this section is very useful even if the programmer wants to perform many tasks
  that are not associated with Perform defined functions.

  The fact that the programmers have to introduce each plugin to the system based on a specific
  behavior is one of the exciting aspects of using this section. Additionally,
  the system has prepared some default behaviors to force the programmers
  to introduce the plugins in the order specified by the system.

  The use of custom behaviors on the part of the programmer and MishkaInstaller itself makes debugging easier;
  however, this library does not leave the programmer to fend for themselves in this significant matter;
  rather, a straightforward error storage system is prepared based on the particular activities being performed.

  Should prevent any unpredictable behavior at any costs.

  ---

  ## Build purpose
  ---

  Imagine you are going to make an application that will have many plugins built for it in the future.
  But the fact that many manipulations will be made on your source code makes it
  difficult to maintain the application.

  For example, you present a content management system for your users, and now they need to
  activate a section for registration and SMS; the system allows you to present your desired
  `input/output` absolutely plugin oriented to your users and makes it possible for the
  developers to write their required applications beyond the core source code.

  ---

  The library categorizes your whole software design structure into many parts;
  and has an appropriate dependency that is optional with `GenServer`;
  it considers a monitoring branch for each of your plugins, which results in fewer errors and `downtime`.

  The considered part:

  1. Behaviors and events
  2. Recalling or `Hook` with priority
  3. `State` management and links to the database (`Mnesia` support)

  > Most of the sections mentioned can be fully customized to suit your needs.
  > This library offers a range of predefined strategies for public use, which might
  > be sufficient for your requirements.

  In Mishka Elixir Plugin Management Library, a series of action or `hook` functions are given
  to the developer of the main plugin or software, which helps build plugins outside the system
  and convert software sections into separate `events`.

  Some of the functions of this module include the following:

  - `config/0` - Retrieves the merged configuration for the hook module.
  - `config/1` - Retrieves a specific configuration value by key.
  - `register/0` - Register a plugin for a specific event.
  - `start/0` - Start a plugin of a specific event.
  - `restart/0` - Restart a plugin of a specific event.
  - `stop/0` - Stop a plugin of a specific event.
  - `unregister/0` - Unregister a plugin of a specific event.
  - `get/0` - Retrieves a Plugin `GenServer` state.

  ### Example:

  ```elixir
  defmodule RegisterEmailSender do
    use MishkaInstaller.Event.Hook, event: "after_success_login"

    def call(entries) do
      {:reply, entries}
    end
  end
  ```

  If you want to change a series of default information, do this:

  ```elixir
  use MishkaInstaller.Event.Hook,
    event: "after_success_login",
    initial: %{depends: [SomeEvent], priority: 20}
  ```

  > There should be one main functions in each plugin, namely `call`. In this function,
  > whenever the action function calls this special event for which the plugin is written,
  > based on priority. This plugin is also called. But what is important is the final output
  > of the `call` function.
  > This output may be the input of other plugins with higher priorities.
  > The order of the plugins is from small to large, and if several plugins are registered for a number,
  > it is sorted by name in the second parameter. And it should be noted that in any case,
  > if you did not want this `state` to go to other plugins and the last output is returned in the same plugin,
  > and you can replace `{:reply, :halt, new_state}` with `{:reply, new_state}`.


  **Note: If you want your plugin to execute automatically,
  all you need to do is send the name of the module in which you utilized
  the `MishkaInstaller.Event.Hook` to the Application module.***

  ```elixir
  children = [
    ...
    RegisterEmailSender
  ]

  ...
  opts = [strategy: :one_for_one, name: SomeModule.Supervisor]
  Supervisor.start_link(children, opts)
  ```

  #### You can call all plugins of an event:

  ```elixir
  alias MishkaInstaller.Event.Hook

  # Normal call an event plugins
  Hook.call("after_success_login", params)

  # If you want certain entries not to change
  Hook.call("after_success_login", params, [private: something_based_on_your_data])

  # If you want the initial entry to be displayed at the end
  Hook.call("after_success_login", params, [return: true])
  ```
  """
  alias MishkaInstaller.Event.{Event, ModuleStateCompiler}

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      use GenServer, restart: :transient
      alias MishkaInstaller.Event.{Event, Hook, EventHandler}
      alias MishkaInstaller.Event.ModuleStateCompiler, as: MSE

      @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}
      @type okey_return :: {:ok, struct() | map() | module() | list(any())}
      # Based on https://elixirforum.com/t/59168/5
      @app_config Mix.Project.config()
      @plugin_event Keyword.get(opts, :event)
      @initial Keyword.get(opts, :initial, %{})
      @plugin_name __MODULE__
      @wait_for_tables 6000
      @after_compile __MODULE__
      @checking Keyword.get(opts, :checking, 1000)

      @spec config() :: keyword()
      def config(),
        do: Keyword.merge(@app_config, __plugin__: @plugin_name, __event__: @plugin_event)

      @spec config(atom()) :: any()
      def config(key), do: Keyword.get(config(), key)

      @spec register() :: okey_return | error_return
      def register() do
        Event.register(config(:__plugin__), config(:__event__), @initial)
      end

      @spec start() :: okey_return | error_return
      def start() do
        Event.start(:name, config(:__plugin__))
      end

      @spec restart() :: okey_return | error_return
      def restart() do
        Event.restart(:name, config(:__plugin__))
      end

      @spec stop() :: okey_return | error_return
      def stop() do
        Event.stop(:name, config(:__plugin__))
      end

      @spec unregister() :: okey_return | error_return
      def unregister() do
        Event.unregister(:name, config(:__plugin__))
      end

      @spec get() :: keyword()
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

      @spec start_link() :: :ignore | {:error, any()} | {:ok, pid()}
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

      @impl true
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

      @impl true
      def handle_info(%{status: :re_event, data: _data}, state) do
        new_state =
          case Event.get(:name, state[:name]) do
            nil -> state
            data -> Keyword.merge(state, status: data.status)
          end

        {:noreply, state}
      end

      @impl true
      def handle_info(:status, state) do
        Process.send_after(__MODULE__, :status, @checking)

        new_state =
          with "ready" <- :persistent_term.get(:event_status, nil),
               {:module, module} <- Code.ensure_loaded(MSE.module_event_name(@plugin_event)),
               data when not is_nil(data) <-
                 Enum.find(module.initialize().plugins, &(&1.name == @plugin_name)),
               plugin <- Event.get(:name, @plugin_name) do
            if is_nil(plugin), do: state, else: Keyword.merge(state, status: plugin.status)
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
  @doc """
  Invokes the `call/2` function of the specified event module.

  ## Parameters
  - `event` (String.t()): The name of the event.
  - `data` (any()): The data to be passed to the event module.
  - `args` (keyword()): Additional arguments for the call (`private`, `return`).

  ## Returns
  - `any()`: The result of the event module's `call/2` function.

  ## Examples
  ```elixir
  MishkaInstaller.Event.Hook.call("my_event", %{}, [])
  ```
  """
  @spec call(String.t(), any(), keyword()) :: any()
  def call(event, data, args \\ []) do
    module = ModuleStateCompiler.module_event_name(event)

    if function_exported?(module, :call, 2) do
      module.call(data, args)
    else
      {:error, :undefined_function_error}
    end
  end

  @doc """
  The only difference between this function and the `call/3` function is that the former
  does not check in a single step whether the required event has been compiled or not.
  When you are 100% certain that the event you want is present in the system,
  using it is the best option.
  """
  @spec call!(String.t(), any(), keyword()) :: any()
  def call!(event, data, args \\ []) do
    module = ModuleStateCompiler.module_event_name(event)
    module.call(data, args)
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  @doc false
  @spec start_helper(module(), keyword(), any()) :: keyword()
  def start_helper(module, state, reg_db_plg) do
    case module.start() do
      {:ok, st_db_plg} ->
        Keyword.merge(state, status: st_db_plg.status, depends: st_db_plg.depends)

      _error ->
        Keyword.merge(state, status: reg_db_plg.status, depends: reg_db_plg.depends)
    end
  end

  @doc false
  @spec register_start_helper(module(), keyword()) :: keyword()
  def register_start_helper(module, state) do
    db_plg = Event.get(:name, module)

    if is_nil(db_plg) do
      case module.register() do
        {:ok, reg_db_plg} ->
          start_helper(module, state, reg_db_plg)

        error ->
          MishkaInstaller.broadcast("event", :register_error, error)
          state
      end
    else
      MishkaInstaller.broadcast("event", :register, db_plg)
      Keyword.merge(state, status: db_plg.status)
    end
  end
end
