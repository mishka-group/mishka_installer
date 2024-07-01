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
  alias MishkaDeveloperTools.Helper.Extra
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
  @spec create(list(struct()), String.t()) :: :ok | error_return
  def create(plugins, event) do
    module = module_event_name(event)
    escaped_plugins = Macro.escape(plugins)

    ast =
      quote do
        defmodule unquote(module) do
          def call(state, args \\ []) do
            private = Keyword.get(args, :private)
            return_status = Keyword.get(args, :return)

            performed =
              unquote(Macro.escape(plugins))
              |> MishkaInstaller.Event.ModuleStateCompiler.perform({:reply, state})

            if !is_nil(return_status) do
              state
            else
              case performed do
                {:ok, data} when is_list(data) ->
                  if Keyword.keyword?(data) and !is_nil(private),
                    do: {:ok, Keyword.merge(data, private)},
                    else: {:ok, data}

                {:ok, data} when is_map(data) ->
                  {:ok, if(!is_nil(private), do: Map.merge(data, private), else: data)}

                {:error, _errors} = errors ->
                  errors

                data when is_list(data) ->
                  if Keyword.keyword?(data) and !is_nil(private),
                    do: Keyword.merge(data, private),
                    else: data

                data when is_map(data) ->
                  if !is_nil(private), do: Map.merge(data, private), else: data
              end
            end
          rescue
            _e -> state
          end

          def initialize?(), do: true

          def initialize() do
            %{module: unquote(module), plugins: unquote(escaped_plugins)}
          end

          def is_changed?([]) do
            [] != unquote(escaped_plugins)
          end

          def is_changed?(new_plugins) do
            !Enum.all?(new_plugins, &(&1 in unquote(escaped_plugins)))
          end

          def is_initialized?(new_plugin) do
            Enum.member?(unquote(escaped_plugins), new_plugin)
          end
        end
      end

    [{^module, _}] = Code.compile_quoted(ast, "#{Extra.randstring(8)}")
    {:module, ^module} = Code.ensure_loaded(module)
    :ok
  rescue
    e in CompileError ->
      {:error, [%{message: e.description, field: :event, action: :compile}]}

    _ ->
      {:error, [%{message: "Unexpected error", field: :event, action: :compile}]}
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
  @spec purge_create(list(struct()), String.t()) :: :ok | error_return
  def purge_create(plugins, event) do
    purge(event)
    create(plugins, event)
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
    module = module_event_name(event)
    :code.purge(module)
    :code.delete(module)
    :ok
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  @doc """
  Generates a module name based on the event name.

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
  def initialize?(event), do: module_event_name(event).initialize?

  @doc """
  Safely checks if the event module is initialized, rescuing any errors.

  ## Examples
  ```elixir
  rescue_initialize?("event_name")
  ```
  """
  @spec rescue_initialize?(String.t()) :: boolean()
  def rescue_initialize?(event) do
    module = module_event_name(event)
    module.initialize?
  rescue
    _ -> false
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
    module = module_event_name(event)
    Code.ensure_loaded?(module)
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
    module = module_event_name(event)
    function_exported?(module, :initialize?, 0)
  end

  @doc false
  @spec perform(list(), {:reply, any()} | {:reply, :halt, any()}) :: any()
  def perform([], {:reply, state}), do: state

  def perform(_plugins, {:reply, :halt, state}), do: state

  def perform([h | t], {:reply, state}) do
    new_state = apply(h.name, :call, [state])
    perform(t, new_state)
  end
end
