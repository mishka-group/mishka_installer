defmodule MishkaInstaller.Reference.OnUserBeforeSave do

  defstruct [:ip, :socket, :session, :output]

  @type user_info() :: map()
  @type session() :: map()
  @type output() :: Phoenix.LiveView.Rendered.t()| nil
  @type socket() :: Phoenix.LiveView.Socket.t()
  @type ip() :: String.t() | tuple() # User's IP from both side endpoints connections
  @type ref() :: :on_user_before_login # Name of this event
  @type reason() :: map() | String.t() # output of state for this event
  @type registerd_info() :: MishkaInstaller.PluginState.t() # information about this plugin on state which was saved
  @type state() :: %__MODULE__{ip: ip(), socket: socket(), session: session(), output: output()}
  @type t :: state() # help developers to keep elixir style
  @type optional_callbacks :: {:ok, ref(), registerd_info()} | {:error, ref(), reason()}

  @callback initial(list()) :: {:ok, ref(), list()} | {:error, ref(), reason()} # Register hook
  @callback call(state()) :: {:reply, state()} | {:reply, :halt, state()}  # Developer should decide what and Hook call function
  @callback stop(registerd_info()) :: optional_callbacks() # Stop of hook module
  @callback start(registerd_info()) :: optional_callbacks() # Start of hook module
  @callback delete(registerd_info()) :: optional_callbacks() # Delete of hook module
  @callback unregister(registerd_info()) :: optional_callbacks() # Unregister of hook module
  @optional_callbacks stop: 1, start: 1, delete: 1, unregister: 1 # Developer can use this callbacks if he/she needs
end
