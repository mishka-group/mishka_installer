defmodule MishkaInstaller.Reference.OnRouter do
  # TODO: Should be rechecked in real-example, consider type of @type and defstruct
  # TODO: Do not use it until a stable version is released
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

  @typedoc "This type can be used when you want to specify which HTTP typing method is your desired"
  @type action() :: :get | :post | :live | :delete | :put | :forward
  @typedoc "This type can be used when you want to specify a path for your custom router"
  @type path() :: String.t()
  # TODO: why this type() was created?
  @type type() :: atom()
  @typedoc "This type can be used when you want to introduce an endpoint module for your router"
  @type endpoint() :: module()
  @typedoc "This type can be used when you want to introduce an app's reference name"
  @type ref() :: :on_router
  @typedoc "This type can be used when you want to introduce a plugin output"
  @type reason() :: map()
  @typedoc "This type can be used when you want to register an app"
  @type registerd_info() :: MishkaInstaller.PluginState.t()
  @typedoc "This type can be used when you want to introduce an app as a plugin"
  @type state() :: %__MODULE__{
          action: action(),
          path: path(),
          endpoint: endpoint(),
          type: type(),
          plug_opts: list()
        }
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
