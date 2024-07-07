defmodule MishkaInstallerTest.Support.MishkaPlugin.Bulk.EventCOTP do
  use MishkaInstaller.Event.Hook, event: "event_c"

  @impl true
  def call(entries) do
    {:reply, entries}
  end
end
