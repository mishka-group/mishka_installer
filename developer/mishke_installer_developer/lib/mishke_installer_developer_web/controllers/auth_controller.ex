defmodule MishkeInstallerDeveloperWeb.AuthController do
  use MishkeInstallerDeveloperWeb, :controller

  def login(conn, %{"email" => "shahryar.tbiz@gmail.com", "password" => "something_as_password"}) do
    render(conn, "login.html")
  end

  def login(conn, %{"params" => entry}) do
    # developer or client should send a map as params key and this map must includ struct which is your module name
    # for example Elixir.MishkaSocial.Auth.Strategy, it should be noted, this module have to have struct under itself
    convert_controller_to_protocol(conn, entry, :login)
  end

  def register(conn, %{"email" => "shahryar.tbiz@gmail.com", "password" => "something_as_password"}) do
    render(conn, "login.html")
  end

  def register(conn, %{"params" => entry}) do
    convert_controller_to_protocol(conn, entry, :register)
  end

  def convert_controller_to_protocol(conn, entry, action) do
    case behaviour_module(entry["struct"]) do
      {:ok, module} ->
        apply(MishkaSocial.AuthProtocol, action, [Map.merge(struct(module), convert_string_map_to_atom(entry, conn))])
      {:error, :module_not_found} -> {:error, :convert_controller_to_protocol}
    end
  end

  defp convert_string_map_to_atom(string_map, conn) do
    string_map
    |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
    |> Map.merge(%{conn: conn})
  end

  defp behaviour_module(module_name) do
    {:ok, String.to_existing_atom(module_name)}
  rescue
    _ ->{:error, :module_not_found}
  end
end
