defmodule MishkaInstaller.Reference.OnUserAfterLogout do
  @moduledoc """
    This event is triggered whenever a user is successfully logged out. if there is any active module in this section on state,
    this module sends a request as a Task tool to the developer call function that includes `user_id()`, `ip()`, `endpoint()`.
    It should be noted; This process does not interfere with the main operation of the system.
    It is just a sender and is active for both side endpoints.
  """
  defstruct [:user_id, :ip, :endpoint, :conn, :extra]

  @type user_id() :: <<_::288>>
  @type extra() :: map() | struct() | list()
  # User's IP from both side endpoints connections
  @type ip() :: String.t() | tuple()
  # API, HTML
  @type endpoint() :: :html | :api
  @type conn() :: Plug.Conn.t()
  # Name of this event
  @type ref() :: :on_user_after_logout
  # output of state for this event
  @type reason() :: map() | String.t()
  # information about this plugin on state which was saved
  @type registerd_info() :: MishkaInstaller.PluginState.t()
  @type state() :: %__MODULE__{
          user_id: user_id(),
          ip: ip(),
          endpoint: endpoint(),
          conn: conn(),
          extra: extra()
        }
  # help developers to keep elixir style
  @type t :: state()
  @type optional_callbacks :: {:ok, ref(), registerd_info()} | {:error, ref(), reason()}

  # Register hook
  @callback initial(list()) :: {:ok, ref(), list()} | {:error, ref(), reason()}
  # Developer should decide what and Hook call function
  @callback call(state()) :: {:reply, state()} | {:reply, :halt, state()}
  # Stop of hook module
  @callback stop(registerd_info()) :: optional_callbacks()
  # Restart of hook module
  @callback restart(registerd_info()) :: optional_callbacks()
  # Start of hook module
  @callback start(registerd_info()) :: optional_callbacks()
  # Delete of hook module
  @callback delete(registerd_info()) :: optional_callbacks()
  # Unregister of hook module
  @callback unregister(registerd_info()) :: optional_callbacks()
  # Developer can use this callbacks if he/she needs
  @optional_callbacks stop: 1, restart: 1, start: 1, delete: 1, unregister: 1
end
