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

  Returns `:ok`, or `{:error, [%{action: :compile, field: :event, message: _}]}` when the module
  cannot be built (a plugin entry that is not a plugin, for example). The module is built in its own
  process, so a failure never raises in the caller.

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
    module = module_event_name(event)
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
    :ok
  end

  # Started-but-not-loaded plugins compile to a stub that runs none of them: it hands back the state,
  # or the caller's `:cannot_run` answer.
  defp call_ast(:error, _event, _plugins) do
    quote do
      def call(state, args \\ []), do: Keyword.get(args, :cannot_run, state)
    end
  end

  defp call_ast(:ok, event, plugins) do
    # One shared `state` var for the param and the unrolled chain.
    state = Macro.var(:state, __MODULE__)

    # `meta` is read-only side context handed to plugins that opt in with `call/2`. When no plugin uses
    # it the var is named `_meta`, so the binding never trips an "unused variable" warning.
    meta = Macro.var(if(any_call2?(plugins), do: :meta, else: :_meta), __MODULE__)

    quote do
      def call(unquote(state), args \\ []) do
        unquote(meta) = Keyword.get(args, :meta)

        performed = unquote(build_chain(plugins, state, meta))

        unquote(__MODULE__).finish_call(performed, unquote(state), args)
      rescue
        e ->
          unquote(__MODULE__).log_call_error(unquote(event), e)
          unquote(state)
      end
    end
  end

  @doc false
  @spec finish_call(any(), any(), keyword()) :: any()
  def finish_call(performed, state, args) do
    case Keyword.get(args, :return) do
      nil -> merge_private(performed, Keyword.get(args, :private))
      _return -> state
    end
  end

  defp merge_private({:ok, data}, private) when is_list(data),
    do: {:ok, merge_list(data, private)}

  defp merge_private({:ok, data}, private) when is_map(data), do: {:ok, merge_map(data, private)}
  defp merge_private({:ok, _data} = ok, _private), do: ok
  defp merge_private({:error, _errors} = errors, _private), do: errors
  defp merge_private(data, private) when is_list(data), do: merge_list(data, private)
  defp merge_private(data, private) when is_map(data), do: merge_map(data, private)
  # Any other state — a LiveView callback's `{:noreply, socket}`, a binary — comes back as the
  # plugins left it; `:private` merges only into a list or a map.
  defp merge_private(other, _private), do: other

  defp merge_list(data, nil), do: data

  defp merge_list(data, private),
    do: if(Keyword.keyword?(data), do: Keyword.merge(data, private), else: data)

  defp merge_map(data, nil), do: data
  defp merge_map(data, private), do: Map.merge(data, private)

  # Unroll the plugin chain into nested calls: `{:reply, state}` continues, `{:reply, :halt, state}` halts.
  # A plugin that defines `call/2` is handed `meta` as a second, read-only argument; `call/1` plugins are
  # invoked exactly as before. The arity is resolved here, at dispatch-compile time, so the hot path stays
  # a direct call with no per-invocation arity check.
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
  @spec log_call_error(String.t(), Exception.t()) :: :ok
  def log_call_error(event, error) do
    Logger.error(
      "[mishka_installer.event] plugin pipeline raised in event #{inspect(event)}: #{inspect(error)}"
    )
  end

  @doc """
  Purges (`purge/1`) an existing module and creates a new one (`create/2`) with the provided plugins and event name.

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
  def purge_create(plugins, event, inaccessible \\ []) do
    module = module_event_name(event)

    # Drop only the old copy then recompile; the current version stays callable until the new one loads.
    :code.purge(module)
    create(plugins, event, inaccessible)
  end

  @doc """
  Purges the specified event modules or a module.

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

      module ->
        :code.purge(module)
        :code.delete(module)
        :ok
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  @doc """
  Returns the module compiled for `event` on this node, or `nil` when `create/3` never built one.

  It only reads the cache that `module_event_name/1` fills, so it never creates an atom or a cache
  key: this is the function to call with an event name that is not known to exist.

  ## Examples
  ```elixir
  event_module("event_name")
  ```
  """
  @spec event_module(String.t()) :: module() | nil
  def event_module(event), do: :persistent_term.get({__MODULE__, :name_cache, event}, nil)

  @doc """
  Generates a module name based on the event name.

  It **creates** the module atom and a `:persistent_term` cache key for a name it has not seen, so
  pass it only the name of an event that is being compiled. `create/3` and `purge_create/3` call it;
  to find the module of an event that may not exist use `event_module/1`.

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
    # Memoize the immutable event->module mapping in `:persistent_term` (hot path, lock-free reads).
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
  def initialize?(event), do: module_event_name(event).initialize?()

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
  Checks if the event module is compiled and loaded.

  > Just should be used when you need one time or in compile time

  ## Examples
  ```elixir
  compile_initialize?("event_name")
  ```
  """
  @spec compile_initialize?(String.t()) :: boolean()
  def compile_initialize?(event) do
    case event_module(event) do
      nil -> false
      module -> Code.ensure_loaded?(module)
    end
  end

  @doc """
  Checks if the event module has an `initialize?` function exported.

  ## Examples
  ```elixir
  safe_initialize?("event_name")
  ```
  """
  @spec safe_initialize?(String.t()) :: boolean()
  def safe_initialize?(event) do
    case event_module(event) do
      nil -> false
      module -> Code.ensure_loaded?(module) and function_exported?(module, :initialize?, 0)
    end
  end
end
