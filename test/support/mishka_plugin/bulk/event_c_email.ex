defmodule MishkaInstallerTest.Support.MishkaPlugin.Bulk.EventCEmail do
  use MishkaInstaller.Event.Hook, event: "event_c"

  def call(entries) do
    {:reply, entries}
  end
end
