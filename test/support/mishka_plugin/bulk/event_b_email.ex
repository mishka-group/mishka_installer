defmodule MishkaInstallerTest.Support.MishkaPlugin.Bulk.EventBEmail do
  use MishkaInstaller.Event.Hook, event: "event_b"

  def call(entries) do
    {:reply, entries}
  end
end
