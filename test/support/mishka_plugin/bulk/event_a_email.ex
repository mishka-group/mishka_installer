defmodule MishkaInstallerTest.Support.MishkaPlugin.Bulk.EventAEmail do
  use MishkaInstaller.Event.Hook, event: "event_a"

  def call(entries) do
    {:reply, entries}
  end
end
