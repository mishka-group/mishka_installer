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

  # Register hook
  @callback initial(list()) :: {:ok, ref(), list()} | {:error, ref(), reason()}
  # Developer should decide what and Hook call function
  @callback call(state()) :: {:reply, state()} | {:reply, :halt, state()}
  # Stop of hook module
  @callback stop(registerd_info()) :: optional_callbacks()
  # Start of hook module
  @callback start(registerd_info()) :: optional_callbacks()
  # Delete of hook module
  @callback delete(registerd_info()) :: optional_callbacks()
  # Unregister of hook module
  @callback unregister(registerd_info()) :: optional_callbacks()
  # Developer can use this callbacks if he/she needs
  @optional_callbacks stop: 1, start: 1, delete: 1, unregister: 1
end
