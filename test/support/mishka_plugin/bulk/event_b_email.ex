defmodule MishkaInstallerTest.Support.MishkaPlugin.Bulk.EventBEmail do
  use MishkaInstaller.Event.Hook, event: "event_b"

  @impl true
  def call(entries) do
    {:reply, entries}
  end
end
