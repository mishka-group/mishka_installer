defmodule MishkaInstaller.Reference.OnRouter do
  @moduledoc """

  ## elixir macros for router
  ```elixir
    live(path, live_view, action \\ nil, opts \\ [])
    live "/", TrackappWeb.Live.DepGetter

    delete(path, plug, plug_opts, options \\ [])
    delete("/events/:id", EventController, :action)

    forward(path, plug, plug_opts \\ [], router_opts \\ [])
    forward "/admin", SomeLib.AdminDashboard

    get(path, plug, plug_opts, options \\ [])
    get("/events/:id", EventController, :action)

    post(path, plug, plug_opts, options \\ [])
    post("/events/:id", EventController, :action)

    put(path, plug, plug_opts, options \\ [])
    put("/events/:id", EventController, :action)
  ```
  """
  defstruct [:action, :path, :endpoint, type: :public, plug_opts: []]

  @type action() :: :get | :post | :live | :delete | :put | :forward
  @type path() :: String.t()
  @type type() :: atom()
  @type endpoint() :: module()
  @type ref() :: :on_router # Name of this event
  @type reason() :: map()
  @type registerd_info() :: MishkaInstaller.PluginState.t() # information about this plugin on state which was saved
  @type state() :: %__MODULE__{action: action(), path: path(), endpoint: endpoint(), type: type(), plug_opts: list()}
  @type t :: state() # help developers to keep elixir style
  @type optional_callbacks :: {:ok, ref(), registerd_info()} | {:error, ref(), reason()}

  @callback initial(list()) :: {:ok, ref(), list()} | {:error, ref(), reason()} # Register hook
  @callback call(state()) :: {:reply, state()} | {:reply, :halt, state()}  # Developer should decide what and Hook call function
  @callback stop(registerd_info()) :: optional_callbacks() # Stop of hook module
  @callback restart(registerd_info()) :: optional_callbacks() # Restart of hook module
  @callback start(registerd_info()) :: optional_callbacks() # Start of hook module
  @callback delete(registerd_info()) :: optional_callbacks() # Delete of hook module
  @callback unregister(registerd_info()) :: optional_callbacks() # Unregister of hook module
  @optional_callbacks stop: 1, restart: 1, start: 1, delete: 1, unregister: 1 # Developer can use this callbacks if he/she needs
end
