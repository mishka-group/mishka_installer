defmodule MishkaInstaller.Reference.OnUserAfterDeleteRole do
  @moduledoc """
    This event is triggered whenever a user's role is successfully deleted. if there is any active module in this section on state,
    this module sends a request as a Task tool to the developer call function that includes `user_info()`, `ip()`, `endpoint()`, `modifier_user()`.
    It should be noted; This process does not interfere with the main operation of the system.
    It is just a sender and is active for both side endpoints.
  """
  defstruct [:role_id, :ip, :endpoint, :conn]

  @typedoc "This type can be used when you want to introduce what `role_id` is required"
  @type role_id() :: <<_::288>>
  @typedoc "This type can be used when you want to get a `user_id` (modifier_user)"
  @type user_id() :: role_id()
  @typedoc "This type can be used when you want to introduce the connection of a user request"
  @type conn() :: Plug.Conn.t() | Phoenix.LiveView.Socket.t()
  @typedoc "This type can be used when you want to get a user' IP"
  @type ip() :: String.t() | tuple()
  @typedoc "This type can be used when you want to introduce an endpoint module for your router"
  @type endpoint() :: :html | :api
  @typedoc "This type can be used when you want to introduce an app's reference name"
  @type ref() :: :on_user_after_delete_role
  @typedoc "This type can be used when you want to introduce a plugin output"
  @type reason() :: map() | String.t()
  @typedoc "This type can be used when you want to register an app"
  @type registerd_info() :: MishkaInstaller.PluginState.t()
  @typedoc "This type can be used when you want to introduce an app as a plugin"
  @type state() :: %__MODULE__{role_id: role_id(), ip: ip(), endpoint: endpoint(), conn: conn()}
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
