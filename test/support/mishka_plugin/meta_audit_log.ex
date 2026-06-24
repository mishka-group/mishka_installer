defmodule MishkaInstallerTest.Support.MishkaPlugin.MetaAuditLog do
  @moduledoc """
  A real plugin that opts into the read-only `meta` context with `call/2`.

  It reads the request context handed in as `meta` (actor / ip / time) and returns a brand-new map
  that merges those audit fields into the event entries — showing that `meta` reaches the plugin while
  the data the plugin produces still flows on through the normal `{:reply, _}` return.
  """
  use MishkaInstaller.Event.Hook, event: "after_user_login"

  @impl true
  def call(entries, meta) do
    audit = %{
      audited_by: meta[:actor],
      audited_ip: meta[:ip],
      audited_at: meta[:at]
    }

    {:reply, Map.merge(entries, audit)}
  end
end
