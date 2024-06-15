defmodule MishkaInstallerTest.Support.MishkaPlugin.EventCDeps do
  alias MishkaInstallerTest.Support.MishkaPlugin.EventCDepsOne

  use MishkaInstaller.Event.Hook,
    event: "event_c_extra",
    initial: %{depends: [EventCDepsOne], priority: 20}

  def call(entries) do
    {:reply, entries}
  end
end
