defmodule MishkaInstallerTest.Support.MishkaPlugin.Bulk.EventAOTP do
  use MishkaInstaller.Event.Hook, event: "event_a"

  def call(entries) do
    {:reply, entries}
  end
end
