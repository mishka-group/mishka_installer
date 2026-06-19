defmodule MishkaInstallerTest.Installer.LibraryHandlerTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Installer.LibraryHandler
  alias MishkaInstallerTest.Support.EbinFixture

  setup do
    System.put_env("PROJECT_PATH", File.cwd!())
    :ok
  end

  test "Read app file" do
    {:ok, data} =
      assert LibraryHandler.read_app(
               :req,
               System.get_env("PROJECT_PATH") <> "/_build/test/lib/req/ebin/req.app"
             )

    assert Keyword.get(data, :vsn) == ~c"0.6.1"
    {:error, _error} = assert LibraryHandler.read_app(:req, "_build/test/lib/req/ebin/req1.app")
    {:error, _error} = assert LibraryHandler.read_app(:req1, "_build/test/lib/req/ebin/req.app")
  end

  test "Application ensure/load is idempotent" do
    :ok = assert LibraryHandler.application_ensure(:req)
    # Calling it again on an already-loaded/started app must still succeed (boot-replay safety).
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
    assert LibraryHandler.extensions_path() =~ "/deployment/test/extensions"
  end

  test "Extensions path can be overridden via application env" do
    Application.put_env(:mishka_installer, :extensions_path, "/tmp/custom-extensions")
    assert LibraryHandler.extensions_path() == "/tmp/custom-extensions"
  after
    Application.delete_env(:mishka_installer, :extensions_path)
  end

  test "Prepend compiled apps adds the ebin to the code path" do
    app = :"lib_handler_prepend_#{System.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), "#{app}")
    {^app, _module, ebin} = EbinFixture.build_fake_app(dir, app, "0.1.0")
    on_exit(fn -> File.rm_rf!(dir) end)

    :ok = assert LibraryHandler.prepend_compiled_apps([{app, ebin}])
    assert String.to_charlist(ebin) in :code.get_path()

    {:error, [%{action: :prepend_compiled_apps}]} =
      assert LibraryHandler.prepend_compiled_apps([{:nope, "/does/not/exist/ebin"}])
  end

  test "Compare version with installed app" do
    # `:req` is installed at 0.6.1 in the test build.
    :ok = assert LibraryHandler.compare_version_with_installed_app(:req, "99.0.0")

    {:error, [%{action: :compare_version_with_installed_app}]} =
      assert LibraryHandler.compare_version_with_installed_app(:req, "0.0.1")

    # An app that is not installed is always allowed.
    :ok =
      assert LibraryHandler.compare_version_with_installed_app(:not_installed_app_xyz, "1.0.0")
  end

  test "Extract a pre-built ebin tarball into the extensions directory" do
    app = :"lib_handler_extract_#{System.unique_integer([:positive])}"
    {tarball, ^app, _module} = EbinFixture.tar_fake_app(app, "0.1.0")
    name = "#{app}-0.1.0"
    dest = "#{LibraryHandler.extensions_path()}/#{name}"
    on_exit(fn -> File.rm_rf!(dest) end)

    :ok = assert LibraryHandler.extract(:tar, tarball, name)
    assert File.dir?("#{dest}/ebin")
    assert File.exists?("#{dest}/ebin/#{app}.app")
  end

  test "Extract rejects an archive without an ebin directory" do
    # A tarball whose only entry is a stray file (no `ebin/`).
    uniq = System.unique_integer([:positive])
    src = Path.join(System.tmp_dir!(), "no-ebin-#{uniq}")
    File.mkdir_p!(src)
    File.write!(Path.join(src, "readme.txt"), "hello")
    tar = Path.join(System.tmp_dir!(), "no-ebin-#{uniq}.tar.gz")

    :ok =
      :erl_tar.create(
        String.to_charlist(tar),
        [{~c"readme.txt", String.to_charlist(Path.join(src, "readme.txt"))}],
        [:compressed]
      )

    tarball = File.read!(tar)
    File.rm_rf!(src)
    File.rm!(tar)

    name = "no-ebin-#{uniq}"
    on_exit(fn -> File.rm_rf!("#{LibraryHandler.extensions_path()}/#{name}") end)

    {:error, [%{action: :extract}]} = assert LibraryHandler.extract(:tar, tarball, name)
  end
end
