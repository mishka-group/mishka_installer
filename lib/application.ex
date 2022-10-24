defmodule MishkaInstaller.Application do
  use Application
  @impl true
  def start(_type, _args) do
    test_mode = if Mix.env() != :test, do: [MishkaInstaller.PluginETS], else: []

    children =
      [
        {Finch, name: SenderClientApi},
        {Finch, name: DownloaderClientApi},
        {Registry, keys: :unique, name: PluginStateRegistry},
        {DynamicSupervisor, [strategy: :one_for_one, name: PluginStateOtpRunner]},
        {DynamicSupervisor,
         [strategy: :one_for_one, name: MishkaInstaller.RunTimeObanSupervisor]},
        {Task.Supervisor, name: MishkaInstaller.Activity},
        {Task.Supervisor, name: DepChangesProtectorTask},
        {Task.Supervisor, name: MishkaInstaller.Installer.DepHandler},
        {Task.Supervisor, name: PluginEtsTask},
        {Phoenix.PubSub, name: MishkaInstaller.PubSub},
        MishkaInstaller.Installer.DepChangesProtector,
        MishkaInstaller.Helper.Setting
      ] ++ test_mode

    opts = [strategy: :one_for_one, name: MishkaInstaller.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
