defmodule MishkaInstaller.Reference.OnContentAfterDelete do
  # TODO: it needs html render
  @moduledoc """
    With the help of this event, you can have information about the content that will be deleted in your plugin.
    This event has no return output. Please use the `operation: :no_return` flag.

    It is currently being renovated, and in the future it might look different.
  """
  defstruct [:section, :private, extra: %{}]

  @typedoc "This type can be used when you want to introduce what place this captcha is going to be run"
  @type section() :: atom()
  @typedoc "This type can be used when you want to introduce a user IP"
  @type user_id() :: <<_::288>>
  @typedoc "This type can be used when you want to introduce an app's reference name"
  @type ref() :: :on_content_after_delete
  @typedoc "This type can be used when you want to introduce a content output"
  @type content() :: map()
  @typedoc "This type can be used when you want to introduce a plugin output"
  @type reason() :: map() | String.t()
  @typedoc "This type can be used when you want to register an app"
  @type registerd_info() :: MishkaInstaller.PluginState.t()
  @typedoc "This type can be used when you want to introduce an IP"
  @type ip() :: String.t() | tuple()
  @typedoc "This type can be used when you want to introduce private properties"
  @type private() :: %{user_id: user_id(), content: content(), user_ip: ip()}
  @typedoc "This type can be used when you want to introduce an app as a plugin"
  @type state() :: %__MODULE__{section: section(), private: private(), extra: map()}
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
