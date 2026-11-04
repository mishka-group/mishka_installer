defmodule MishkaInstaller.Event.ModuleStateCompiler do
  @moduledoc """
  `The MishkaInstaller.Event.ModuleStateCompiler` module is designed to dynamically create and manage
  event-driven modules that handle state and plugins within the Mishka Installer system.
  This module provides functions to create, purge, and verify the initialization state of these event modules.

  **In fact, this system creates a runtime module for each event based on system
  requirements and conditions in the `MishkaInstaller.Event.Event` and `MishkaInstaller.Event.Hook` modules,
  which also contains a series of essential functions.**

  ---

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > This module is a read-only in-memory storage optimized for the fastest possible read times
  > not for write strategies.

  ##### Compile path: `MishkaInstaller.Event.ModuleStateCompiler.State.YourEvent`.

  ### Note:

  When you are writing, you should always make an effort to be more careful because
  you might get reconditioned during times of high traffic.
  When it comes to reading and running all plugins, this problem only occurs when a
  module is being created and destroyed during the compilation process.
  """
  require Logger
  alias MishkaInstaller.Helper.Extra
  @state_dir "MishkaInstaller.Event.ModuleStateCompiler.State."
  @slot_dir "Elixir.MishkaInstaller.Event.ModuleStateCompiler.State"

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}
  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @doc """
  Creates a new module based on the provided event name and plugins.

  ## Parameters
  - `plugins` (list): A list of plugin(`ishkaInstaller.Event.Event`) structs to be included in the
  new module.
  - `event` (String.t()): The name of the event for which the module is created.
  - `inaccessible` (list): The plugins of the chain that are started but not loaded. When it is not
  empty, the module's `call/2` runs none of the plugins: it answers the `:cannot_run` option, or the
  state it was given when there is none, and `mode/0` is `:error`.

  When a plugin of the module's `call/2` raises, or replies with something other than
  `{:reply, state}` or `{:reply, :halt, state}`, the plugins after it do not run, the exception is
  logged with its stacktrace, and `call/2` answers the `:raised` option, or the state it was given
  when there is none.

  Returns `:ok`, or `{:error, [%{action: :compile, field: :event, message: _}]}` when the module
  cannot be built (a plugin entry that is not a plugin, for example). The module is built in its own
  process, so a failure never raises in the caller.

  Once the module is loaded, `event_module/1` finds it, so `MishkaInstaller.Event.Hook.call/3`
  starts running it. A failed build leaves the lookup as it was: the module built before keeps
  answering, and an event that never built one has none.

  A build never stops a process that is still running an earlier version, for example a caller
  waiting inside a slow plugin. Loading a module over an old version that a process still runs
  would kill that process, so the new version goes into the event's own module name
  (`module_event_name/1`) when no process runs its old version (`:code.soft_purge/1`), and
  otherwise into the next free slot (`...ModuleStateCompiler.State1.YourEvent`, and so on). The
  caller finishes on the version it entered, and later calls run the new one. Once nothing runs
  the old version, the next build goes back to the event's own name, so an event uses more than one
  slot only while a caller outlives two builds. Each build also drops every other slot that no
  process runs, except the one that answered until this build: a caller that looked it up just
  before still finds it.

  The generated `is_changed?/1` compares the incoming chain with the compiled one by **equality**,
  so a plugin leaving the chain — a stopped plugin, or one held by a dependency — is detected just
  like a plugin joining it, and `MishkaInstaller.Event.EventHandler` rebuilds the module.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measure

  ## Examples
  ```elixir
  alias MishkaInstaller.Event.Event
  create([%Event{name: MyPlugin}], "event_name")
  ```
  """
  @spec create(list(struct()), String.t(), list(module())) :: :ok | error_return
  def create(plugins, event, inaccessible \\ []) do
    case Extra.isolate(fn -> compile_event(plugins, event, inaccessible) end) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        Logger.error(
          "[mishka_installer.event] the module of event #{inspect(event)} was not compiled: " <>
            inspect(reason)
        )

        {:error,
         [
           %{
             message: "The module of the event could not be compiled.",
             field: :event,
             action: :compile
           }
         ]}
    end
  end

  defp compile_event(plugins, event, inaccessible) do
    base = module_event_name(event)
    previous = event_module(event)
    module = free_slot(event, base, 0)
    escaped_plugins = Macro.escape(plugins)
    mode = if inaccessible == [], do: :ok, else: :error

    ast =
      quote do
        defmodule unquote(module) do
          unquote(call_ast(mode, event, plugins))

          def mode(), do: unquote(mode)

          def initialize?(), do: true

          def initialize() do
            %{module: unquote(module), plugins: unquote(escaped_plugins)}
          end

          # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
          def is_changed?(new_plugins) do
            new_plugins != unquote(escaped_plugins)
          end

          # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
          def is_initialized?(new_plugin) do
            Enum.member?(unquote(escaped_plugins), new_plugin)
          end
        end
      end

    # Recompiling replaces the current version of an already-loaded module; silence the conflict.
    Code.put_compiler_option(:ignore_module_conflict, true)
    [{^module, _}] = Code.compile_quoted(ast, "#{Extra.randstring(8)}")
    {:module, ^module} = Code.ensure_loaded(module)
    # An atom value: putting the same one again is a no-op, and erasing it needs no global GC.
    :persistent_term.put(compiled_key(event), module)
    retire_idle(event, base, [module, previous])
    :ok
  end

  # Started-but-not-loaded plugins compile to a stub that runs none of them: it hands back the state,
  # or the caller's `:cannot_run` answer.
  defp call_ast(:error, _event, _plugins) do
    quote do
      def call(state, args \\ []) when is_list(args), do: Keyword.get(args, :cannot_run, state)
    end
  end

  # One shared `state` var for the param and the unrolled chain. `meta` is read from the args only
  # when a plugin of the chain takes it with `call/2`, so a chain of `call/1` plugins never scans them.
  defp call_ast(:ok, event, plugins) do
    state = Macro.var(:state, __MODULE__)
    meta = Macro.var(:meta, __MODULE__)
    chain = build_chain(plugins, state, meta)

    performed =
      if any_call2?(plugins) do
        quote do
          unquote(meta) = Keyword.get(args, :meta)
          unquote(chain)
        end
      else
        chain
      end

    # `finish_call/3` runs in the `else` of the `try`, outside the rescue: a bad `:return` or
    # `:private` is the caller's ArgumentError, never reported as a plugin crash. The `try` stays
    # explicit because a function-level `else` reads as a mistake.
    quote do
      def call(unquote(state), args \\ []) when is_list(args) do
        # credo:disable-for-next-line Credo.Check.Readability.PreferImplicitTry
        try do
          unquote(performed)
        rescue
          e ->
            unquote(__MODULE__).log_call_error(unquote(event), e, __STACKTRACE__)
            Keyword.get(args, :raised, unquote(state))
        else
          performed -> unquote(__MODULE__).finish_call(performed, unquote(state), args)
        end
      end
    end
  end

  @doc false
  @spec finish_call(any(), any(), keyword()) :: any()
  def finish_call(performed, _state, []), do: performed

  def finish_call(performed, state, args) do
    case Keyword.get(args, :return) do
      nil -> merge_private(performed, Keyword.get(args, :private))
      _return -> state
    end
  end

  # `:private` is a map or a keyword list; anything else is the caller's ArgumentError.
  defp merge_private(data, nil), do: data
  defp merge_private(data, private) when is_map(private), do: merge_into(data, private)

  defp merge_private(data, private) when is_list(private) do
    if Keyword.keyword?(private),
      do: merge_into(data, private),
      else: raise(ArgumentError, private_error(private, "a map or a keyword list"))
  end

  defp merge_private(_data, private),
    do: raise(ArgumentError, private_error(private, "a map or a keyword list"))

  defp merge_into({:ok, data}, private) when is_list(data) or is_map(data),
    do: {:ok, merge_into(data, private)}

  defp merge_into(data, private) when is_map(data) and is_map(private),
    do: Map.merge(data, private)

  defp merge_into(data, private) when is_map(data), do: Map.merge(data, Map.new(private))
  defp merge_into(data, private) when is_list(data), do: merge_list(data, private)

  # Any other state — a LiveView callback's `{:noreply, socket}`, `{:error, _}`, a binary — comes
  # back as the plugins left it; `:private` merges only into a list or a map.
  defp merge_into(other, _private), do: other

  defp merge_list(data, private),
    do: if(Keyword.keyword?(data), do: Keyword.merge(data, keyword(private)), else: data)

  defp keyword(private) when is_list(private), do: private

  defp keyword(private) do
    pairs = Map.to_list(private)

    if Keyword.keyword?(pairs),
      do: pairs,
      else: raise(ArgumentError, private_error(private, "a map with atom keys or a keyword list"))
  end

  defp private_error(private, expected),
    do:
      "the :private option of MishkaInstaller.Event.Hook.call/3 must be #{expected} to merge " <>
        "into the result, got: #{inspect(private)}"

  # Unroll the plugin chain into nested calls: `{:reply, state}` continues, `{:reply, :halt, state}` halts.
  # A plugin that defines `call/2` is handed `meta` as a second, read-only argument; `call/1` plugins are
  # invoked exactly as before. The arity is resolved here, at dispatch-compile time. `apply/3` with a
  # literal module, function and argument list compiles to the same direct remote call, and keeps the
  # type checker from warning on every build that a plugin which never halts makes the halt clause
  # unreachable.
  defp build_chain([], state_var, _meta_var), do: state_var

  defp build_chain([plugin | rest], state_var, meta_var) do
    next = Macro.unique_var(:state, __MODULE__)
    call_args = if call2?(plugin), do: [state_var, meta_var], else: [state_var]

    quote do
      case apply(unquote(plugin.name), :call, unquote(call_args)) do
        {:reply, :halt, halted} -> halted
        {:reply, unquote(next)} -> unquote(build_chain(rest, next, meta_var))
      end
    end
  end

  defp any_call2?(plugins), do: Enum.any?(plugins, &call2?/1)

  defp call2?(plugin),
    do: Code.ensure_loaded?(plugin.name) and function_exported?(plugin.name, :call, 2)

  @doc false
  @spec log_call_error(String.t(), Exception.t(), Exception.stacktrace()) :: :ok
  def log_call_error(event, error, stacktrace) do
    Logger.error(
      "[mishka_installer.event] a plugin of event #{inspect(event)} raised: " <>
        Exception.format(:error, error, stacktrace)
    )
  end

  @doc """
  Rebuilds the module of an event with the provided plugins: the same as `create/3`, which already
  replaces an earlier version without stopping a process that still runs it.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measure

  ## Examples
  ```elixir
  alias MishkaInstaller.Event.Event
  purge_create([%Event{name: MyPlugin}], "event_name")
  ```
  """
  @spec purge_create(list(struct()), String.t(), list(module())) :: :ok | error_return
  def purge_create(plugins, event, inaccessible \\ []), do: create(plugins, event, inaccessible)

  @doc """
  Purges the specified event modules or a module.

  The event leaves the `event_module/1` lookup before its code is deleted, so
  `MishkaInstaller.Event.Hook.call/3` answers the state it is given from then on, as for an event
  that was never compiled. A process still running a version of the event finishes on it: that
  version is dropped once nothing runs it, at the latest by the event's next build. When nothing
  runs any version, the event's `:persistent_term` keys go too.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measure

  ## Examples
  ```elixir
  purge("event_name")
  ```
  """
  @spec purge(list(String.t()) | String.t()) :: :ok
  def purge(events) when is_list(events) do
    Enum.each(events, &purge(&1))
    :ok
  end

  def purge(event) do
    case event_module(event) do
      nil ->
        :ok

      _module ->
        :persistent_term.erase(compiled_key(event))

        if retire_idle(event, module_event_name(event), []) do
          :persistent_term.erase({__MODULE__, :last_slot, event})
          :persistent_term.erase({__MODULE__, :name_cache, event})
        end

        :ok
    end
  end

  # Drops every slot of the event but `keep` that no process runs, and answers whether all of them
  # are gone. A slot that is neither loaded nor holds an old version costs two BIF checks.
  defp retire_idle(event, base, keep) do
    for index <- 0..last_slot(event),
        module = slot(base, index),
        module not in keep,
        reduce: true do
      gone? -> retire(module) and gone?
    end
  end

  # The module a new version of the event is loaded into: the first slot whose old version no
  # process runs. A slot whose old version is still running is skipped, never purged.
  defp free_slot(event, base, index) do
    module = slot(base, index)

    if :code.soft_purge(module) do
      remember_slot(event, index)
      module
    else
      free_slot(event, base, index + 1)
    end
  end

  defp slot(base, 0), do: base

  defp slot(base, index) do
    "Elixir." <> @state_dir <> name = Atom.to_string(base)
    String.to_atom(@slot_dir <> Integer.to_string(index) <> "." <> name)
  end

  # The highest slot an event used, kept as a small integer so updating it needs no global GC.
  defp last_slot(event), do: :persistent_term.get({__MODULE__, :last_slot, event}, 0)

  defp remember_slot(event, index) do
    if index > last_slot(event), do: :persistent_term.put({__MODULE__, :last_slot, event}, index)
  end

  # Drops a slot's code and answers whether it is gone. A version a process still runs stays, and a
  # later build drops it once it is free.
  defp retire(module) do
    if :erlang.module_loaded(module) or :erlang.check_old_code(module) do
      :code.soft_purge(module) and drop_current(module)
    else
      true
    end
  end

  defp drop_current(module) do
    :code.delete(module)
    :code.soft_purge(module)
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  @doc """
  Returns the module compiled for `event` on this node, or `nil` when `create/3` never built one
  or `purge/1` removed it.

  A module is in this lookup only while it is loaded, so the answer can be called without checking
  its exports first. It is one `:persistent_term` read, never creates an atom or a key, and is the
  function to call with an event name that is not known to exist.

  ## Examples
  ```elixir
  event_module("event_name")
  ```
  """
  @spec event_module(String.t()) :: module() | nil
  def event_module(event), do: :persistent_term.get(compiled_key(event), nil)

  defp compiled_key(event), do: {__MODULE__, :compiled, event}

  @doc """
  Generates a module name based on the event name.

  It **creates** the module atom and a `:persistent_term` cache key for a name it has not seen, so
  pass it only the name of an event that is being compiled. `create/3` and `purge_create/3` call it;
  to find the module of an event that may not exist use `event_module/1`.

  It is the event's own module name, which runs the event unless a caller outlived two builds (see
  `create/3`); `event_module/1` always answers the module that runs it now.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measure

  ## Examples
  ```elixir
  module_event_name("event_name")
  ```
  """
  @spec module_event_name(String.t()) :: module()
  def module_event_name(event) do
    case :persistent_term.get({__MODULE__, :name_cache, event}, nil) do
      nil ->
        module = build_module_name(event)
        :persistent_term.put({__MODULE__, :name_cache, event}, module)
        module

      module ->
        module
    end
  end

  defp build_module_name(event) do
    event
    |> String.trim()
    |> String.replace(" ", "_")
    |> then(&Regex.replace(~r/^\d+/, &1, ""))
    |> Macro.camelize()
    |> then(&String.to_atom(@state_dir <> &1))
    |> then(&Module.concat([&1]))
  end

  @doc """
  Checks if the event module is initialized.

  ## Examples
  ```elixir
  initialize?("event_name")
  ```
  """
  @spec initialize?(String.t()) :: boolean()
  def initialize?(event), do: event_module(event).initialize?()

  @doc """
  Checks if the event module is initialized, answering `false` for an event that is not compiled
  instead of raising.

  ## Examples
  ```elixir
  rescue_initialize?("event_name")
  ```
  """
  @spec rescue_initialize?(String.t()) :: boolean()
  def rescue_initialize?(event) do
    safe_initialize?(event) and event_module(event).initialize?()
  end

  @doc """
  Checks if the event module is compiled and loaded: `event_module/1` finds it.

  ## Examples
  ```elixir
  compile_initialize?("event_name")
  ```
  """
  @spec compile_initialize?(String.t()) :: boolean()
  def compile_initialize?(event), do: not is_nil(event_module(event))

  @doc """
  Checks if the event module is loaded, so its `initialize?/0` can be called: `event_module/1`
  finds it.

  ## Examples
  ```elixir
  safe_initialize?("event_name")
  ```
  """
  @spec safe_initialize?(String.t()) :: boolean()
  def safe_initialize?(event), do: not is_nil(event_module(event))
end
