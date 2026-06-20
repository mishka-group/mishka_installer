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

  > #### Use cases information {: .tip}
  >
  > Module `MishkaInstaller.Event.Event` has all of the preset functionalities, and it is
  > simple for you to build and implement your own strategy because of this.
  >
  > You can override these functions:
  > `register: 0`, `start: 0`, `restart: 0`, `stop: 0`, `unregister: 0`, `get: 0`

  ### Consideration:

  It should be brought to your attention that the output of the `call` function has a few trade-offs.
  These trade-offs do not restrict your ability to customize the outcome of the `call` function;
  nevertheless, they do cause you to move away from the foreseen and planned structure that is the
  approach that this library takes.

  In situations when you have access to a `:private` key, it is preferable for your data to be in the
  form of a `Map` or a `Keyword`. This allows you to perform an accurate match prior to the
  output of the data.
  With the exception of these two circumstances, we do not collect any other data.

  ---

  The list below is all the outputs that are checked in the form of different wrist patterns:

  ```elixir
  {:ok, data} when is_list(data) # It can be merged with the `:private` key
  {:ok, data} when is_map(data) # It can be merged with the `:private` key
  # If you have :private, we do not recommend to use this pattern
  {:ok, data} # It can not be merged with the `:private` key
  {:error, _errors} # It does not need to be merged
  data when is_list(data) # It can be merged with the `:private` key
  data when is_map(data) # It can be merged with the `:private` key
  ```

  ### For example:

  We do not recommend these the data or error data; they should have `Map` or `Keyword` format.

  ```elixir
  def call(entries) do
    {:reply, :halt, {:ok, "Message is sent!"}}
  end

  def call(entries) do
    {:reply, entries}
  end
  ```

  But it is recommended to use these.

  ```elixir
  def call(entries) do
    {:reply, :halt, {:ok, %{name: "mishka"}}
  end

  def call(entries) do
    {:reply, {:ok, [name: "mishka"]}
  end

  def call(entries) do
    {:reply, {:error, any_data}
  end
  ```

  > #### Use cases information {: .tip}
  >
  > Take note that you have the ability to set the `queue` of a plugin to `false` while
  > you are defining it. This will ensure that the implementation and build of
  > the event state module are not **queued**.
  >
  > For projects that require a significant amount of time to compile their events module,
  > this possibility has been implemented. Additionally, these projects may have created a
  > series of conditions in order to avoid race conditions from occurring within their system.
  >
  > It is `true` by default and recommend to set `false` till you get some problem.

  ##### Example:
  ```elixir
  use MishkaInstaller.Event.Hook, event: "after_success_login", queue: false
  ```

  [![Run in Livebook](https://livebook.dev/badge/v1/pink.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fmishka-group%2Fmishka_installer%2Fblob%2Fmaster%2Fguidance%2Fevent%2Fhook.livemd)
  """
  alias MishkaInstaller.Event.{Event, EventHandler, ModuleStateCompiler}

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}
  @type okey_return :: {:ok, struct() | map() | module() | list(any())}

  @callback call(any()) :: any()
  @callback register() :: okey_return | error_return
  @callback start() :: okey_return | error_return
  @callback restart() :: okey_return | error_return
  @callback stop() :: okey_return | error_return
  @callback unregister() :: okey_return | error_return
  @callback get() :: keyword()
  @callback health_check() :: :ok | {:degraded, term()} | {:error, term()}
  @optional_callbacks register: 0,
                      start: 0,
                      restart: 0,
                      stop: 0,
                      unregister: 0,
                      get: 0,
                      health_check: 0

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      use GenServer, restart: :transient
      @behaviour MishkaInstaller.Event.Hook
      alias MishkaInstaller.Event.{Event, Hook, EventHandler}
      alias MishkaInstaller.Event.ModuleStateCompiler, as: MSE

      @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}
      @type okey_return :: {:ok, struct() | map() | module() | list(any())}
      # Based on https://elixirforum.com/t/59168/5
      # Only keep basic config values that can be serialized at compile time
      @app_config Mix.Project.config()
                  |> Keyword.take([
                    :app,
                    :version,
                    :elixir,
                    :deps,
                    :name,
                    :source_url,
                    :homepage_url,
                    :description
                  ])
                  |> Keyword.filter(fn {_k, v} ->
                    is_atom(v) or is_binary(v) or is_list(v) or is_map(v) or is_number(v) or
                      is_nil(v)
                  end)
      @plugin_event Keyword.get(opts, :event)
      @initial Keyword.get(opts, :initial, %{})
      @plugin_name __MODULE__
      @after_compile __MODULE__
      @checking Keyword.get(opts, :checking, 1000)
      @queue Keyword.get(opts, :queue, true)

      # `config/0` carries the plugin's compile-time options so the shared `Hook.*` functions below
      # can read them at runtime; everything else in this macro is a thin delegator (the real logic
      # lives once in `MishkaInstaller.Event.Hook`, not recompiled into every plugin).
      @spec config() :: keyword()
      def config() do
        Keyword.merge(@app_config,
          __plugin__: @plugin_name,
          __event__: @plugin_event,
          __initial__: @initial,
          __queue__: @queue,
          __checking__: @checking
        )
      end

      @spec config(atom()) :: any()
      def config(key), do: Keyword.get(config(), key)

      @spec register() :: okey_return | error_return
      def register(), do: Hook.plugin_register(__MODULE__)

      @spec start() :: okey_return | error_return
      def start(), do: Hook.plugin_start(__MODULE__)

      @spec restart() :: okey_return | error_return
      def restart(), do: Hook.plugin_restart(__MODULE__)

      @spec stop() :: okey_return | error_return
      def stop(), do: Hook.plugin_stop(__MODULE__)

      @spec unregister() :: okey_return | error_return
      def unregister(), do: Hook.plugin_unregister(__MODULE__)

      @spec get() :: keyword()
      def get(), do: Hook.plugin_get(__MODULE__)

      @doc "Optional. See `c:MishkaInstaller.Event.Hook.on_dependency_error/1`. Override to react."
      @spec on_dependency_error(term()) :: term()
      def on_dependency_error(error), do: Hook.default_dependency_error(error)

      @doc "Optional. See `c:MishkaInstaller.Event.Hook.health_check/0`. Override to report health."
      @spec health_check() :: :ok | {:degraded, term()} | {:error, term()}
      def health_check(), do: Hook.default_health_check()

      defoverridable register: 0,
                     start: 0,
                     restart: 0,
                     stop: 0,
                     unregister: 0,
                     get: 0,
                     on_dependency_error: 1,
                     health_check: 0

      def __after_compile__(_env, _bytecode), do: Hook.after_compile(__MODULE__)

      @spec start_link() :: :ignore | {:error, any()} | {:ok, pid()}
      def start_link(args \\ []), do: Hook.plugin_start_link(__MODULE__, args)

      @impl true
      def init(state), do: Hook.plugin_init(__MODULE__, state)

      @impl true
      def handle_continue(:start_plugin, state), do: Hook.plugin_continue(__MODULE__, state)

      @impl true
      def handle_call(:get, _from, state), do: {:reply, state, state}
      def handle_call(_reason, _from, state), do: {:reply, state, state}

      @impl true
      def handle_info(:start_again, state), do: Hook.plugin_start_again(__MODULE__, state)

      def handle_info(%{status: status, data: data}, state)
          when status in [:start, :stop, :unregister],
          do: Hook.plugin_dependency_event(__MODULE__, data, state)

      def handle_info(%{status: :re_event, data: _data}, state),
        do: Hook.plugin_re_event(state)

      def handle_info(:status, state), do: Hook.plugin_status_poll(__MODULE__, state)

      def handle_info(_reason, state), do: {:noreply, state}
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
    if function_exported?(module, :call, 2), do: module.call(data, args), else: data
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

  @doc """
  Profiles an event's compiled plugin chain: runs each plugin once with `state` and returns how long
  each took, in microseconds, in execution order.

  This is a **development/debugging** helper. It runs the same plugins as `call/3` but is a separate,
  off-the-hot-path function, so production dispatch keeps zero profiling overhead. For a visual flame
  graph, add [`flame_on`](https://hexdocs.pm/flame_on) to your host app's `LiveDashboard` and profile
  `MishkaInstaller.Event.Hook.call/3`.

  Returns `{:ok, [%{plugin: module(), microseconds: non_neg_integer()}]}` or `{:error, :not_compiled}`.
  """
  @spec profile(String.t(), any()) :: {:ok, [map()]} | {:error, :not_compiled}
  def profile(event, state) do
    module = ModuleStateCompiler.module_event_name(event)

    if function_exported?(module, :initialize, 0) do
      {_final, timings} =
        Enum.reduce(module.initialize().plugins, {state, []}, fn plugin, {acc_state, acc} ->
          {micros, next} = time_plugin(plugin.name, acc_state)
          {next, [%{plugin: plugin.name, microseconds: micros} | acc]}
        end)

      {:ok, Enum.reverse(timings)}
    else
      {:error, :not_compiled}
    end
  end

  # Cold path (profiling only) — a rescue here is fine and keeps one slow/failing plugin from
  # aborting the whole profile run.
  defp time_plugin(name, state) do
    :timer.tc(fn ->
      case apply(name, :call, [state]) do
        {:reply, new_state} -> new_state
        other -> other
      end
    end)
  rescue
    _ -> {0, state}
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Health (▰˘◡˘▰) ############################
  ####################################################################################
  @health_timeout 1000

  @doc """
  Health report for a single plugin. Combines built-in checks — process `alive?`, module
  `callable?`, registry `status` — with the plugin's optional `c:health_check/0` probe (run in a
  time-boxed process, so it never blocks the plugin or the caller).

  `probe` is `:ok | {:degraded, reason} | {:error, reason}` (with `{:error, :timeout}`,
  `{:error, :no_health_check}`, `{:error, {:raised, _}}` ... for the failure variants). `healthy?`
  is the overall verdict.
  """
  @spec plugin_health(module(), timeout()) :: map()
  def plugin_health(name, timeout \\ @health_timeout) do
    db = Event.get(:name, name)
    alive? = is_pid(Process.whereis(name))
    callable? = Code.ensure_loaded?(name) and function_exported?(name, :call, 1)
    status = db && db.status
    probe = run_health(name, timeout)

    %{
      plugin: name,
      status: status,
      alive?: alive?,
      callable?: callable?,
      probe: probe,
      healthy?: alive? and callable? and probe == :ok and status in [:started, :restarted]
    }
  end

  @doc """
  Health report for an event: whether its module is compiled, its `mode` (`:error` means it has
  plugins that are started but not loaded — see issue #1), and a report for each plugin in the
  chain. Plugin probes run concurrently and time-boxed. `healthy?` is the overall verdict.
  """
  @spec event_health(String.t(), timeout()) :: map()
  def event_health(event, timeout \\ @health_timeout) do
    module = ModuleStateCompiler.module_event_name(event)
    compiled? = function_exported?(module, :initialize, 0)
    mode = if function_exported?(module, :mode, 0), do: module.mode(), else: :unknown
    plugins = if compiled?, do: module.initialize().plugins, else: []

    reports =
      plugins
      |> Task.async_stream(&plugin_health(&1.name, timeout),
        timeout: timeout + 1000,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(plugins)
      |> Enum.map(fn
        {{:ok, report}, _pl} -> report
        {{:exit, reason}, pl} -> unhealthy_report(pl.name, {:error, {:exit, reason}})
      end)

    %{
      event: event,
      compiled?: compiled?,
      mode: mode,
      plugin_count: length(reports),
      plugins: reports,
      healthy?: compiled? and mode == :ok and Enum.all?(reports, & &1.healthy?)
    }
  end

  @doc "Health report for every event in the system. See `event_health/2`."
  @spec health(timeout()) :: [map()]
  def health(timeout \\ @health_timeout) do
    case Event.group_events() do
      {:ok, events} -> Enum.map(events, &event_health(&1, timeout))
      _ -> []
    end
  end

  @doc """
  Runs a plugin's `c:health_check/0` probe in a short-lived monitored process, bounded by `timeout`.
  Never blocks the plugin's `GenServer` and never crashes the caller: a slow probe yields
  `{:error, :timeout}`, a raising/exiting one `{:error, {:raised | :exit, _}}`, a non-conforming
  return `{:error, {:bad_return, _}}`, and a plugin without the callback `{:error, :no_health_check}`.
  """
  @spec run_health(module(), timeout()) :: :ok | {:degraded, term()} | {:error, term()}
  def run_health(plugin, timeout \\ @health_timeout) do
    if function_exported?(plugin, :health_check, 0) do
      {pid, ref} =
        spawn_monitor(fn -> exit({:health_probe, safe_probe(plugin)}) end)

      receive do
        {:DOWN, ^ref, :process, ^pid, {:health_probe, result}} -> result
        {:DOWN, ^ref, :process, ^pid, reason} -> {:error, {:exit, reason}}
      after
        timeout ->
          Process.exit(pid, :kill)
          Process.demonitor(ref, [:flush])
          {:error, :timeout}
      end
    else
      {:error, :no_health_check}
    end
  end

  defp safe_probe(plugin) do
    normalize_probe(plugin.health_check())
  rescue
    e -> {:error, {:raised, e}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp normalize_probe(:ok), do: :ok
  defp normalize_probe({:degraded, _} = degraded), do: degraded
  defp normalize_probe({:error, _} = error), do: error
  defp normalize_probe(other), do: {:error, {:bad_return, other}}

  defp unhealthy_report(name, probe) do
    %{plugin: name, status: nil, alive?: false, callable?: false, probe: probe, healthy?: false}
  end

  ####################################################################################
  ################# (▰˘◡˘▰) Plugin runtime (macro delegates here) (▰˘◡˘▰) ######
  ####################################################################################
  # `use MishkaInstaller.Event.Hook` injects only thin wrappers that call the functions below, so
  # this logic is compiled once here instead of into every plugin module (faster compile, no
  # duplicated bytecode). Each takes the plugin `module` and reads its compile-time options from
  # `module.config/1`.
  @wait_for_tables 6000

  @doc false
  def plugin_register(module),
    do:
      Event.register(
        module.config(:__plugin__),
        module.config(:__event__),
        module.config(:__initial__)
      )

  @doc false
  def plugin_start(module),
    do: Event.start(:name, module.config(:__plugin__), module.config(:__queue__))

  @doc false
  def plugin_restart(module),
    do: Event.restart(:name, module.config(:__plugin__), module.config(:__queue__))

  @doc false
  def plugin_stop(module),
    do: Event.stop(:name, module.config(:__plugin__), module.config(:__queue__))

  @doc false
  def plugin_unregister(module),
    do: Event.unregister(:name, module.config(:__plugin__), module.config(:__queue__))

  @doc false
  def plugin_get(module), do: GenServer.call(module, :get)

  @doc false
  def plugin_start_link(module, args), do: GenServer.start_link(module, args, name: module)

  @doc false
  def default_health_check(), do: :ok

  @doc false
  def default_dependency_error(error), do: error

  @doc false
  def after_compile(module) do
    if !Module.defines?(module, {:call, 1}),
      do: raise("#{inspect(module)} should have call/1 function.")

    if is_nil(module.config(:__event__)),
      do: raise("#{inspect(module)} should be dedicated to an event.")
  end

  @doc false
  def plugin_init(module, state) do
    MishkaInstaller.subscribe("event")

    new_state =
      Keyword.merge(state, name: module, event: module.config(:__event__), status: :starting)

    {:ok, new_state, {:continue, :start_plugin}}
  end

  @doc false
  def plugin_continue(module, state) do
    MishkaInstaller.MnesiaAssistant.Table.wait_for_tables([Event], @wait_for_tables)

    new_state =
      if ready?() do
        register_start_helper(module, state)
      else
        Process.send_after(module, :start_again, 1000)
        state
      end

    Process.send_after(module, :status, module.config(:__checking__))
    {:noreply, new_state}
  end

  @doc false
  def plugin_start_again(module, state) do
    event = Keyword.get(state, :event)
    db_plg = Event.get(:name, Keyword.get(state, :name))
    state_module = ModuleStateCompiler.module_event_name(event)

    new_state =
      if ModuleStateCompiler.safe_initialize?(event) and state_module.is_initialized?(db_plg) do
        Keyword.merge(state, status: db_plg.status, depends: db_plg.depends)
      else
        if is_nil(db_plg),
          do: register_start_helper(module, state),
          else: start_helper(module, state, db_plg)
      end

    {:noreply, new_state}
  end

  @doc false
  def plugin_dependency_event(module, data, state) do
    event = Keyword.get(state, :event)
    depends = Keyword.get(state, :depends, [])

    new_state =
      with true <- ready?(),
           true <- event == Map.get(data, :event),
           true <- Map.get(data, :name) in depends,
           :ok <- Event.allowed_events?(depends),
           {:ok, struct} <- Event.write(:name, module, %{status: :restarted}),
           _ok <- EventHandler.do_compile(struct.event, :re_event) do
        Keyword.merge(state, status: :restarted)
      else
        _ -> state
      end

    {:noreply, new_state}
  end

  @doc false
  def plugin_re_event(state) do
    new_state =
      case Event.get(:name, state[:name]) do
        nil -> state
        data -> Keyword.merge(state, status: data.status)
      end

    {:noreply, new_state}
  end

  @doc false
  def plugin_status_poll(module, state) do
    Process.send_after(module, :status, module.config(:__checking__))

    new_state =
      with "ready" <- :persistent_term.get(:event_status, nil),
           "ready" <- :persistent_term.get(:compile_status, nil),
           {:module, state_module} <-
             Code.ensure_loaded(ModuleStateCompiler.module_event_name(module.config(:__event__))),
           data when not is_nil(data) <-
             Enum.find(state_module.initialize().plugins, &(&1.name == module)),
           plugin <- Event.get(:name, module) do
        if is_nil(plugin), do: state, else: Keyword.merge(state, status: plugin.status)
      else
        _ -> state
      end

    {:noreply, new_state}
  end

  defp ready?() do
    :persistent_term.get(:event_status, nil) == "ready" and
      :persistent_term.get(:compile_status, nil) == "ready"
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
          module.on_dependency_error(error)
          MishkaInstaller.broadcast("event", :register_error, error)
          state
      end
    else
      MishkaInstaller.broadcast("event", :register, db_plg)
      Keyword.merge(state, status: db_plg.status)
    end
  end
end
