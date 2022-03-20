defmodule MishkeInstallerDeveloperWeb.LiveTestPage do
  use MishkeInstallerDeveloperWeb, :live_view

  @impl true
  def render(assigns) do
    Phoenix.View.render(MishkeInstallerDeveloperWeb.PageView, "live_test_page.html", assigns)
  end

  @impl true
  def mount(_params, _session, socket) do
    new_socket = assign(socket, page_title: "Live Test Page", self_pid: self())
    {:ok, new_socket}
  end
end
