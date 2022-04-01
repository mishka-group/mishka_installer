defmodule MishkeInstallerDeveloperWeb.PageController do
  use MishkeInstallerDeveloperWeb, :controller

  def index(conn, params) do
    IO.inspect(params)
    render(conn, "index.html")
  end
end
