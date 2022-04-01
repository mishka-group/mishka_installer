defmodule MishkeInstallerDeveloperWeb.LiveTestPageOne do
  use MishkeInstallerDeveloperWeb, :live_view

  @impl true
  def render(assigns) do
    Phoenix.View.render(MishkeInstallerDeveloperWeb.PageView, "live_test_page_one.html", assigns)
  end

  @impl true
  def mount(params, _session, socket) do
    user_ip = get_connect_info(socket, :peer_data).address
    new_socket = assign(socket, page_title: "Live Test Page One", self_pid: self(), user_ip: user_ip, input: params)
    {:ok, new_socket}
  end
end
