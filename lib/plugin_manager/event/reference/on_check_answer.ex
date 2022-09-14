defmodule MishkaInstaller.Reference.OnCheckAnswer do
  @moduledoc """
    Event called to initialize the captcha you want. Do not enable more than 1 captcha.

    **Note**: This event is called directly in the html and will have an output

    It is currently being renovated, and in the future it might look different.
  """
  defstruct [:section, :private]

  @typedoc "This type can be used when you want to introduce what place this captcha is going to be run"
  @type section() :: atom()
  @typedoc "This type can be used when you want to introduce an app's reference name"
  @type ref() :: :on_check_answer
  @typedoc "This type can be used when you want to introduce a plugin output"
  @type reason() :: map() | String.t()
  @typedoc "This type can be used when you want to register an app"
  @type registerd_info() :: MishkaInstaller.PluginState.t()
  @typedoc "This type can be used when you want to introduce an IP"
  @type ip() :: String.t() | tuple()
  @typedoc "This type can be used when you want to introduce private properties"
  @type private() :: %{ip: ip()}
  @typedoc "This type can be used when you want to introduce an app as a plugin"
  @type state() :: %__MODULE__{section: section(), private: private()}
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
