defmodule MishkaInstallerTest.Support.MishkaPlugin.EventCDepsOne do
  use MishkaInstaller.Event.Hook, event: "event_c_extra"

  def call(entries) do
    {:reply, entries}
  end
end
