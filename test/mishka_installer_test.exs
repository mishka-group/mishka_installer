defmodule MishkaInstallerTest do
  use ExUnit.Case

  test "Subscribe, Broadcast, Unsubscribe" do
    :ok = assert MishkaInstaller.subscribe("mnesia")
    :ok = assert MishkaInstaller.broadcast("mnesia", :test_start, %{})
    :ok = assert MishkaInstaller.unsubscribe("mnesia")
    :ok = assert MishkaInstaller.broadcast("mnesia", :test, %{}, false)
  end

  test "Project __information__" do
    orig_path = System.get_env("PROJECT_PATH")
    orig_env = System.get_env("MIX_ENV")

    on_exit(fn ->
      reset_env("PROJECT_PATH", orig_path)
      reset_env("MIX_ENV", orig_env)
    end)

    System.delete_env("MIX_ENV")
    System.put_env("PROJECT_PATH", "/")

    %{env: :test, path: "/"} = assert MishkaInstaller.__information__()

    System.put_env("MIX_ENV", "dev")

    %{env: :dev, path: "/"} = assert MishkaInstaller.__information__()
  end

  defp reset_env(key, nil), do: System.delete_env(key)
  defp reset_env(key, value), do: System.put_env(key, value)
end
