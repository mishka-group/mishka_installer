defmodule MishkaInstaller.Reference.OnChangeDependency do
  @moduledoc """
    **Note**: Please do not use it, it will be changed in the next version

    This event is kicked off anytime a plugin is moved into the installation or update stage of the process.
    In the event that a plugin from this area is carrying out the after completing all the above-mentioned procedures,
    the developer will have access to the output in real time.

    **Note**: Treat this event as a no return flag while analyzing it.

    It is currently being renovated, and in the future it might look different.
  """
  defstruct [:app, :status, :output]

  @typedoc "This type can be used when you want to introduce an app"
  @type app() :: atom()
  @typedoc "This type can be used when you want to introduce each line of compiling/installing"
  @type output() :: String.t()
  @typedoc "This type can be used when you want to introduce an app's status"
  @type status() :: :add | :update | :force_update
  @typedoc "This type can be used when you want to introduce an app's reference name"
  @type ref() :: :on_change_dependency
  @typedoc "This type can be used when you want to introduce a plugin output"
  @type reason() :: map() | String.t()
  @typedoc "This type can be used when you want to register an app"
  @type registerd_info() :: MishkaInstaller.PluginState.t()
  @typedoc "This type can be used when you want to introduce an app as a plugin"
  @type state() :: %__MODULE__{app: app(), status: state(), output: output()}
  @typedoc "This type can be used when you want to introduce an app as a plugin"
  @type t :: state()
  @typedoc "This type can be used when you want to show the output of optional callbacks"
  @type optional_callbacks :: {:ok, ref(), registerd_info()} | {:error, ref(), reason()}

  @doc "This Callback can be used when you want to register a plugin"
  @callback initial(list()) :: {:ok, ref(), list()} | {:error, ref(), reason()}
  @doc "This Callback can be used when you want to call a plugin"
  @callback call(state()) :: {:reply, state()} | {:reply, :halt, state()}
  @doc "This Callback can be used when you want to stop a plugin"
  @callback stop(registerd_info()) :: optional_callbacks()
  @doc "This Callback can be used when you want to restart a plugin"
  @callback restart(registerd_info()) :: optional_callbacks()
  @doc "This Callback can be used when you want to start a plugin"
  @callback start(registerd_info()) :: optional_callbacks()
  @doc "This Callback can be used when you want to delete a plugin"
  @callback delete(registerd_info()) :: optional_callbacks()
  @doc "This Callback can be used when you want to unregister a plugin"
  @callback unregister(registerd_info()) :: optional_callbacks()
  # Developer can use this callbacks if he/she needs
  @optional_callbacks stop: 1, restart: 1, start: 1, delete: 1, unregister: 1
end
