defmodule MishkaInstaller.Reference.OnUserBeforeLogin do
  defstruct [:ip, :assigns, :output, :input]

  @type input() :: map()
  @type assigns() :: Phoenix.LiveView.Socket.assigns()
  @type output() :: Phoenix.LiveView.Rendered.t() | nil
  # User's IP from both side endpoints connections
  @type ip() :: String.t() | tuple()
  # Name of this event
  @type ref() :: :on_user_before_login
  # output of state for this event
  @type reason() :: map() | String.t()
  # information about this plugin on state which was saved
  @type registerd_info() :: MishkaInstaller.PluginState.t()
  @type state() :: %__MODULE__{ip: ip(), assigns: assigns(), input: input(), output: output()}
  # help developers to keep elixir style
  @type t :: state()
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
