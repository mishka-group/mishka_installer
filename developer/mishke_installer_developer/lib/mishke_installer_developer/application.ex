defmodule MishkeInstallerDeveloper.Application do
  use Application

  @impl true
  def start(_type, _args) do
    plugin_runner_config = [
      strategy: :one_for_one,
      name: PluginStateOtpRunner
    ]

    children = [
      # Start the Ecto repository
      MishkeInstallerDeveloper.Repo,
      # Start the Telemetry supervisor
      MishkeInstallerDeveloperWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: MishkeInstallerDeveloper.PubSub},
      # Start the Endpoint (http/https)
      MishkeInstallerDeveloperWeb.Endpoint,
      # Start a worker by calling: MishkeInstallerDeveloper.Worker.start_link(arg)
      # {MishkeInstallerDeveloper.Worker, arg}
      {Registry, keys: :unique, name: PluginStateRegistry},
      {DynamicSupervisor, plugin_runner_config},
      {Task.Supervisor, name: MishkaInstaller.Activity},
      %{id: MishkaSocial.Auth.Strategy, start: {MishkaSocial.Auth.Strategy, :start_link, [[]]}}
    ]

    opts = [strategy: :one_for_one, name: MishkeInstallerDeveloper.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MishkeInstallerDeveloperWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
