defmodule MishkaInstallerTest do
  use ExUnit.Case

  test "Subscribe, Broadcast, Unsubscribe" do
    :ok = assert MishkaInstaller.subscribe("mnesia")
    :ok = assert MishkaInstaller.broadcast("mnesia", :test_start, %{})
    :ok = assert MishkaInstaller.unsubscribe("mnesia")
    :ok = assert MishkaInstaller.broadcast("mnesia", :test, %{}, false)
  end

  test "Project __information__" do
    System.put_env("PROJECT_PATH", "/")

    %{env: :test, path: "/"} = assert MishkaInstaller.__information__()

    System.put_env("MIX_ENV", "dev")

    %{env: :dev, path: "/"} = assert MishkaInstaller.__information__()
  end
end
