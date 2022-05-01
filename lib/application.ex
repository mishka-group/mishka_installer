defmodule MishkaInstaller.Application do
  use Application
  alias MsihkaSendingEmailPlugin.{SendingEmail, SendingSMS, SendingHalt}
  @impl true
  def start(_type, _args) do
    plugin_runner_config = [
      strategy: :one_for_one,
      name: PluginStateOtpRunner
    ]

    test_plugin = if Mix.env in [:test] do
      [
        %{id: SendingEmail, start: {SendingEmail, :start_link, [[]]}},
        %{id: SendingSMS, start: {SendingSMS, :start_link, [[]]}},
        %{id: SendingHalt, start: {SendingHalt, :start_link, [[]]}}
      ]
    else
      []
    end

    children = [
      MishkaInstaller.Installer.DepChangesProtector,
      {Registry, keys: :unique, name: PluginStateRegistry},
      {DynamicSupervisor, plugin_runner_config},
      {Task.Supervisor, name: MishkaInstaller.Activity}
    ] ++ test_plugin

    opts = [strategy: :one_for_one, name: MishkaInstaller.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
