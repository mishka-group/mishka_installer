defmodule MishkaInstallerTest.Installer.LibraryHandlerTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Installer.LibraryHandler

  setup do
    System.put_env("PROJECT_PATH", File.cwd!())
  end

  test "Compile an Elixir Library with cmd - command_execution" do
    System.put_env("PROJECT_PATH", File.cwd!())
    temp_name = "elixir-uuid-1.2.1"
    File.rm_rf(File.cwd!() <> "/deployment/test/extensions/#{temp_name}")
    path = "test/support/elixir-uuid-1.2.1.tar.gz"
    File.mkdir!(File.cwd!() <> "/deployment/test/extensions/#{temp_name}")
    :ok = LibraryHandler.extract(:tar, path, temp_name)

    :ok =
      assert LibraryHandler.do_compile(%{
               app: "elixir-uuid",
               version: "1.2.1",
               compile_type: :cmd
             })

    # move_and_replace_build_files
    {:ok, moved_files} =
      assert LibraryHandler.move_and_replace_build_files(%{
               app: "elixir-uuid",
               version: "1.2.1"
             })

    # Prepend compiled apps of an Library
    :ok = assert LibraryHandler.prepend_compiled_apps(moved_files)

    File.rm_rf(File.cwd!() <> "/_build/test/lib/elixir_uuid")

    File.rm_rf(File.cwd!() <> "/deployment/test/extensions/#{temp_name}")
  end

  test "Compile an Elixir Library with port - command_execution" do
    System.put_env("PROJECT_PATH", File.cwd!())
    temp_name = "uuid-1.2.2"
    File.rm_rf(System.get_env("PROJECT_PATH") <> "/deployment/test/extensions/#{temp_name}")
    path = "test/support/elixir-uuid-1.2.1.tar.gz"
    File.mkdir!(System.get_env("PROJECT_PATH") <> "/deployment/test/extensions/#{temp_name}")
    LibraryHandler.extract(:tar, path, temp_name)

    :ok =
      assert LibraryHandler.do_compile(%{
               app: "uuid",
               version: "1.2.2",
               compile_type: :port
             })

    File.rm_rf(File.cwd!() <> "/deployment/test/extensions/#{temp_name}")
  end

  test "Compile an Elixir Library with mix - command_execution" do
    {:error, _error} =
      assert LibraryHandler.do_compile(%{
               app: "elixir-uuid",
               version: "1.2.1",
               compile_type: :mix
             })
  end

  test "Extract and move tar file" do
    System.put_env("PROJECT_PATH", File.cwd!())
    temp_name = "test1"
    File.rm_rf(File.cwd!() <> "/deployment/test/extensions/#{temp_name}")
    path = "test/support/elixir-uuid-1.2.1.tar.gz"
    :ok = LibraryHandler.extract(:tar, path, temp_name)

    path1 = "test/support/mishka_developer_tools-0.1.8.tar.gz"
    {:error, _error} = assert LibraryHandler.extract(:tar, path1, temp_name)
    File.rm_rf(File.cwd!() <> "/deployment/test/extensions/#{temp_name}")
  end

  test "Read app file" do
    System.put_env("PROJECT_PATH", File.cwd!())

    {:ok, data} =
      assert LibraryHandler.read_app(
               :req,
               System.get_env("PROJECT_PATH") <> "/_build/test/lib/req/ebin/req.app"
             )

    assert Keyword.get(data, :vsn) == ~c"0.5.7"
    {:error, _error} = assert LibraryHandler.read_app(:req, "_build/test/lib/req/ebin/req1.app")
    {:error, _error} = assert LibraryHandler.read_app(:req1, "_build/test/lib/req/ebin/req.app")
  end

  test "Application ensure/load" do
    Application.stop(:req)
    Application.unload(:req)
    :ok = assert LibraryHandler.application_ensure(:req)
    {:error, _error} = assert LibraryHandler.application_ensure(:req1)
  end

  test "Application unload" do
    Application.stop(:req)
    assert is_nil(Enum.find(Application.started_applications(), &(elem(&1, 0) == :req)))
    assert !is_nil(Enum.find(Application.loaded_applications(), &(elem(&1, 0) == :req)))
    :ok = assert LibraryHandler.unload(:req)
    assert is_nil(Enum.find(Application.loaded_applications(), &(elem(&1, 0) == :req)))
    :ok = assert LibraryHandler.unload(:req1)
    {:error, _error} = assert LibraryHandler.unload(:logger)
    LibraryHandler.application_ensure(:req)
  end

  test "Extensions path" do
    "/deployment/test/extensions" =~ assert LibraryHandler.extensions_path()
  end

  test "Mix command_execution error" do
    {:error, _error} = assert LibraryHandler.command_execution(:mix, "", "")
  end
end
