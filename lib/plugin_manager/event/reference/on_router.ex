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

    scope "/" do
      pipe_through :browser
      Enum.map(["1", "2"], fn x ->
        live("/x", TrackappWeb.Live.DepGetter)
      end)
    end
  ```
  """
  defstruct [:action, :path, :endpoint, type: :public, plug_opts: []]

  @type action() :: :get | :post | :live | :delete | :put | :forward
  @type path() :: String.t()
  @type type() :: atom()
  @type endpoint() :: module()
  # Name of this event
  @type ref() :: :on_router
  @type reason() :: map()
  # information about this plugin on state which was saved
  @type registerd_info() :: MishkaInstaller.PluginState.t()
  @type state() :: %__MODULE__{
          action: action(),
          path: path(),
          endpoint: endpoint(),
          type: type(),
          plug_opts: list()
        }
  # help developers to keep elixir style
  @type t :: state()
  @type optional_callbacks :: {:ok, ref(), registerd_info()} | {:error, ref(), reason()}

  @doc "This type can be used when you want to register a plugin"
  @callback initial(list()) :: {:ok, ref(), list()} | {:error, ref(), reason()}
  @doc "This type can be used when you want to call a plugin"
  @callback call(state()) :: {:reply, state()} | {:reply, :halt, state()}
  @doc "This type can be used when you want to stop a plugin"
  @callback stop(registerd_info()) :: optional_callbacks()
  @doc "This type can be used when you want to restart a plugin"
  @callback restart(registerd_info()) :: optional_callbacks()
  @doc "This type can be used when you want to start a plugin"
  @callback start(registerd_info()) :: optional_callbacks()
  @doc "This type can be used when you want to delete a plugin"
  @callback delete(registerd_info()) :: optional_callbacks()
  @doc "This type can be used when you want to unregister a plugin"
  @callback unregister(registerd_info()) :: optional_callbacks()
  # Developer can use this callbacks if he/she needs
  @optional_callbacks stop: 1, restart: 1, start: 1, delete: 1, unregister: 1
end
