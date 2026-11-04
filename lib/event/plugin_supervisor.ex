defmodule MishkaInstaller.Event.PluginSupervisor do
  @moduledoc """
  Runs a list of plugins as one group in your own supervision tree, with its own restart budget.

  Put it anywhere in your application's tree, with a `:name` and the plugin modules:

  ```elixir
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: MyApp.PubSub},
      {MishkaInstaller.Event.PluginSupervisor, name: MyApp.Plugins, plugins: plugins()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
  ```

  Options:

  - `:plugins` (required): the plugin modules, each a `use MishkaInstaller.Event.Hook` module or
    any child spec.
  - `:name`: registers the group and is its child id, so two groups can sit under one parent.
    Without it the id is this module.
  - `:max_restarts` and `:max_seconds`: the group's restart intensity, Elixir's 3 in 5 seconds
    unless given.

  The group is a plain `:one_for_one` `Supervisor`: plugins depend on each other through `depends`
  in the registry, not through process links, so one plugin's death never restarts the others.
  A burst of plugin deaths spends the group's budget; when it is spent, only the group stops, its
  parent starts it again, and the parent's other children keep running. `Supervisor.which_children/1`
  on the name lists the group's plugins.

  Listing plugin modules straight in any supervisor keeps working. A group only keeps a crash storm
  of plugins (Mnesia coming up late, for example) away from the rest of the tree.

  ## What happens when a plugin process dies

  A plugin's process drives its lifecycle (register, start, a status poll); it is not on the call
  path. `MishkaInstaller.Event.Hook.call/3` runs the event's compiled module in the caller's
  process, so:

  - The supervisor starts it again (`restart: :transient`). The new process registers again, an
    upsert that keeps the stored status: nothing is unregistered, stopped or held.
  - The event keeps running the plugin while its process is down, even after its supervisor gave
    up. `MishkaInstaller.Event.Hook.plugin_health/2` reports `alive?: false`.
  - `unregister/0` stops the process with `:normal`, so it is not started again.
    `Supervisor.terminate_child/2` does not switch a plugin off; `stop/0` does, and leaves the
    process running.
  - The process is named after its module, so a plugin runs once per node: starting it in a second
    group answers `{:error, {:already_started, pid}}`.
  """
  use Supervisor

  @doc """
  The child spec of a group: a supervisor whose id is its `:name`, or this module without one.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Starts the group with the plugins of `:plugins`. See the module documentation for the options.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    {plugins, opts} = Keyword.pop!(opts, :plugins)
    {limits, opts} = Keyword.split(opts, [:max_restarts, :max_seconds])
    Supervisor.start_link(__MODULE__, {plugins, limits}, opts)
  end

  @impl true
  def init({plugins, limits}),
    do: Supervisor.init(plugins, [strategy: :one_for_one] ++ limits)
end
