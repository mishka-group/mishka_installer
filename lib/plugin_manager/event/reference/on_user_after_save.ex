defmodule MishkaInstaller.Reference.OnUserAfterSave do
  @moduledoc """
    This event is triggered whenever a user is successfully added or edited. if there is any active module in this section on state,
    this module sends a request as a Task tool to the developer call function that includes `user_info()`, `ip()`, `endpoint()`.
    It should be noted; This process does not interfere with the main operation of the system.
    It is just a sender and is active for both side endpoints.
  """
  defstruct [:user_info, :ip, :endpoint, :status, :conn, :modifier_user, :extra]

  @type modifier_user() :: <<_::288>> | :self
  @type user_info() :: map()
  @type status() :: :added | :edited
  @type conn() :: Plug.Conn.t() | Phoenix.LiveView.Socket.t()
  @type extra() :: map() | struct() | list()
  # User's IP from both side endpoints connections
  @type ip() :: String.t() | tuple()
  # API, HTML
  @type endpoint() :: :html | :api
  # Name of this event
  @type ref() :: :on_user_after_save
  # output of state for this event
  @type reason() :: map() | String.t()
  # information about this plugin on state which was saved
  @type registerd_info() :: MishkaInstaller.PluginState.t()
  @type state() :: %__MODULE__{
          user_info: user_info(),
          ip: ip(),
          endpoint: endpoint(),
          status: status(),
          conn: conn(),
          modifier_user: modifier_user(),
          extra: extra()
        }
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
