defmodule MishkaInstallerTest.Support.MishkaPlugin.RegisterOTPSender do
  use MishkaInstaller.Event.Hook, event: "after_success_login"

  def call(entries) do
    {:reply, entries}
  end
end
