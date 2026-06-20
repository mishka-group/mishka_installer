defmodule MishkaInstallerTest.Installer.InstallerTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Installer.{Installer, LibraryHandler, Downloader}
  alias MishkaInstallerTest.Support.EbinFixture

  setup do
    System.put_env("PROJECT_PATH", File.cwd!())
    tmp_dir = System.tmp_dir!()

    mnesia_dir =
      "#{Path.join(tmp_dir, "mishka-installer-#{MishkaInstaller.Helper.UUID.generate()}")}"

    on_exit(fn ->
      pid = Process.whereis(MishkaInstaller.MnesiaRepo)

      if !is_nil(pid) and Process.alive?(pid) do
        GenServer.stop(MishkaInstaller.MnesiaRepo)
      end
    end)

    Process.register(self(), :__mishka_installer_test__)

    Application.put_env(:mishka_installer, MishkaInstaller.MnesiaRepo,
      mnesia_dir: mnesia_dir,
      essential: [Installer]
    )

    MishkaInstaller.subscribe("mnesia")

    start_supervised!(MishkaInstaller.MnesiaRepo)

    assert_receive %{status: :synchronized, channel: "mnesia", data: _data}

    :ok
  end

  ###################################################################################
  ########################## (▰˘◡˘▰) QueryTest (▰˘◡˘▰) ########################
  ###################################################################################
  describe "Installer Table CRUD QueryTest ===>" do
    test "Create a Library record" do
      {:error, _error} = assert Installer.write(%{})

      {:ok, _data} =
        assert Installer.write(%{
                 app: "mishka_developer_tools",
                 version: "0.1.5",
                 path: "mishka_developer_tools"
               })
    end

    test "Read a Library/Libraries records" do
      assert Installer.get() == []

      {:ok, _data} =
        assert Installer.write(%{app: "mishka_developer_tools", version: "0.1.5", path: "p"})

      assert Installer.get() != []
      assert !is_nil(Installer.get(:app, "mishka_developer_tools"))
    end

    test "Update a Library record" do
      {:ok, _data} =
        assert Installer.write(%{app: "mishka_developer_tools", version: "0.1.5", path: "p"})

      get_data = Installer.get() |> List.first()

      {:ok, struct} =
        assert Installer.write({:root, Map.merge(get_data, %{version: "0.1.6"}), :edit})

      assert struct.version == "0.1.6"
      get_data1 = Installer.get() |> List.first()
      assert get_data1.id == get_data.id
      {:ok, struct} = assert Installer.write(:id, get_data.id, %{tag: "1.0.0"})
      assert Installer.get(struct.id).tag == "1.0.0"
    end

    test "All keys of Libraries Record" do
      {:ok, _data} =
        assert Installer.write(%{app: "mishka_developer_tools", version: "0.1.5", path: "p"})

      assert length(Installer.ids()) == 1
    end

    test "Unique? Library Record by app" do
      {:ok, _data} =
        assert Installer.write(%{app: "mishka_developer_tools", version: "0.1.5", path: "p"})

      assert !is_nil(Installer.get(:app, "mishka_developer_tools"))
      assert is_nil(Installer.get(:app, "mishka_developer_tools1"))
    end

    test "Delete Library Record" do
      {:ok, _data} =
        assert Installer.write(%{app: "mishka_developer_tools", version: "0.1.5", path: "p"})

      assert Installer.get() != []
      {:ok, _data} = Installer.delete(:app, "mishka_developer_tools")
      assert Installer.get() == []
    end

    test "Drop all Library records" do
      {:ok, _data} =
        assert Installer.write(%{app: "mishka_developer_tools", version: "0.1.5", path: "p"})

      assert Installer.get() != []
      {:ok, :atomic} = assert Installer.drop()
      assert Installer.get() == []
    end
  end

  ###################################################################################
  ######################## (▰˘◡˘▰) FunctionsTest (▰˘◡˘▰) ######################
  ###################################################################################
  describe "Installer Module FunctionsTest ===>" do
    test "install a local pre-built ebin (:path) loads the app and persists the record" do
      {app, app_atom, version, pkg, module} = fake_local_app()
      on_exit(fn -> cleanup(app_atom, pkg) end)

      {:ok, output} = assert Installer.install(%{app: app, version: version, path: pkg})

      assert output.extension.app == app
      assert output.extension.prepend_paths == [{app_atom, "#{pkg}/ebin"}]
      assert Installer.get(:app, app).version == version
      assert app_atom in started_apps()
      assert module.hello() == :world
    end

    test "install a downloaded pre-built ebin (:url) via Req.Test" do
      Application.put_env(:mishka_installer, :downloader_req_options,
        plug: {Req.Test, Downloader}
      )

      app = uniq_app("url_demo")
      app_atom = String.to_atom(app)
      version = "0.1.0"
      {tarball, ^app_atom, module} = EbinFixture.tar_fake_app(app_atom, version)
      dest = "#{LibraryHandler.extensions_path()}/#{app}-#{version}"

      Req.Test.stub(Downloader, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/gzip", nil)
        |> Plug.Conn.send_resp(200, tarball)
      end)

      on_exit(fn -> cleanup(app_atom, dest) end)

      {:ok, _output} =
        assert Installer.install(%{
                 app: app,
                 version: version,
                 type: :url,
                 path: "https://cdn.example.com/#{app}.tar.gz"
               })

      assert app_atom in started_apps()
      assert module.hello() == :world
      assert File.dir?("#{dest}/ebin")
    end

    test "install a pre-built ebin from a GitHub release (:github_latest_release) via Req.Test" do
      Application.put_env(:mishka_installer, :downloader_req_options,
        plug: {Req.Test, Downloader}
      )

      app = uniq_app("gh_demo")
      app_atom = String.to_atom(app)
      version = "0.1.0"
      {tarball, ^app_atom, module} = EbinFixture.tar_fake_app(app_atom, version)
      dest = "#{LibraryHandler.extensions_path()}/#{app}-#{version}"

      # GitHub API call -> release JSON; the asset (served from a CDN) -> the tarball.
      Req.Test.stub(Downloader, fn conn ->
        if String.contains?(conn.request_path, "/releases") do
          Req.Test.json(conn, %{
            "assets" => [
              %{
                "name" => "#{app}.tar.gz",
                "browser_download_url" => "https://cdn.example.com/#{app}.tar.gz"
              }
            ]
          })
        else
          conn
          |> Plug.Conn.put_resp_content_type("application/gzip", nil)
          |> Plug.Conn.send_resp(200, tarball)
        end
      end)

      on_exit(fn -> cleanup(app_atom, dest) end)

      {:ok, _output} =
        assert Installer.install(%{
                 app: app,
                 version: version,
                 type: :github_latest_release,
                 path: "owner/#{app}"
               })

      assert app_atom in started_apps()
      assert module.hello() == :world
      assert File.dir?("#{dest}/ebin")
    end

    test "restart persistence: the installed app is re-loaded from the record + on-disk ebin" do
      {app, app_atom, version, pkg, module} = fake_local_app()

      on_exit(fn ->
        cleanup(app_atom, pkg)
        :code.purge(module)
        :code.delete(module)
      end)

      {:ok, _} = assert Installer.install(%{app: app, version: version, path: pkg})
      assert app_atom in started_apps()

      # Simulate a server restart: code path + loaded/started state are in-memory only and gone.
      :ok = Application.stop(app_atom)
      :ok = Application.unload(app_atom)
      Code.delete_path("#{pkg}/ebin")
      :code.delete(module)
      :code.purge(module)
      refute app_atom in Enum.map(Application.loaded_applications(), &elem(&1, 0))

      # Boot replay: CompileHandler re-activates every installed app once Mnesia is synchronized.
      test_pid = self()
      handler = {__MODULE__, make_ref()}

      :telemetry.attach(
        handler,
        [:mishka_installer, :installer, :replay],
        fn event, _meas, meta, _ -> send(test_pid, {:telemetry, event, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      pid = start_supervised!(MishkaInstaller.Installer.CompileHandler)
      send(pid, %{status: :synchronized, channel: "mnesia"})

      assert_receive %{status: :compile_synchronized, channel: "mnesia"}, 2000

      assert_receive {:telemetry, [:mishka_installer, :installer, :replay],
                      %{app: ^app, result: :ok}},
                     2000

      # The app is back purely from the persisted record + the on-disk ebin (no reinstall, no mix).
      assert app_atom in started_apps()
      assert String.to_charlist("#{pkg}/ebin") in :code.get_path()
      assert module.hello() == :world
      assert :persistent_term.get(:compile_status) == "ready"
    end

    test "rejects a path outside the extensions directory (path traversal)" do
      {:error, [%{action: :allowed_extract_path}]} =
        assert Installer.install(%{
                 app: "evil_app",
                 version: "1.0.0",
                 type: :path,
                 path: "/tmp/evil-#{System.unique_integer([:positive])}"
               })
    end

    test "rejects an invalid app name (atom-table safety)" do
      {:error, [%{action: :valid_name}]} =
        assert Installer.install(%{app: "../../etc", version: "1.0.0", path: "whatever"})
    end

    test "rejects re-installing the same version of an already running app" do
      {app, app_atom, version, pkg, _module} = fake_local_app()
      on_exit(fn -> cleanup(app_atom, pkg) end)

      {:ok, _} = assert Installer.install(%{app: app, version: version, path: pkg})

      {:error, [%{action: :compare_version_with_installed_app}]} =
        assert Installer.install(%{app: app, version: version, path: pkg})
    end

    test "a corrupt .app aborts install with no record and no loaded app" do
      app = uniq_app("bad_demo")
      pkg = "#{LibraryHandler.extensions_path()}/#{app}-0.1.0"
      File.mkdir_p!("#{pkg}/ebin")
      File.write!("#{pkg}/ebin/#{app}.app", "this is not a valid erlang term")
      on_exit(fn -> File.rm_rf!(pkg) end)

      {:error, _error} = assert Installer.install(%{app: app, version: "0.1.0", path: pkg})
      assert is_nil(Installer.get(:app, app))
      refute String.to_atom(app) in Enum.map(Application.loaded_applications(), &elem(&1, 0))
    end

    test "verifies a matching checksum on a downloaded artifact" do
      Application.put_env(:mishka_installer, :downloader_req_options,
        plug: {Req.Test, Downloader}
      )

      app = uniq_app("sum_ok")
      app_atom = String.to_atom(app)
      version = "0.1.0"
      {tarball, ^app_atom, module} = EbinFixture.tar_fake_app(app_atom, version)
      checksum = :crypto.hash(:sha256, tarball) |> Base.encode16(case: :lower)
      dest = "#{LibraryHandler.extensions_path()}/#{app}-#{version}"
      stub_download(tarball)
      on_exit(fn -> cleanup(app_atom, dest) end)

      {:ok, _} =
        assert Installer.install(%{
                 app: app,
                 version: version,
                 type: :url,
                 path: "https://cdn.example.com/#{app}.tar.gz",
                 checksum: checksum
               })

      assert module.hello() == :world
    end

    test "rejects a mismatched checksum and installs nothing" do
      Application.put_env(:mishka_installer, :downloader_req_options,
        plug: {Req.Test, Downloader}
      )

      app = uniq_app("sum_bad")
      app_atom = String.to_atom(app)
      version = "0.1.0"
      {tarball, ^app_atom, _module} = EbinFixture.tar_fake_app(app_atom, version)
      stub_download(tarball)

      on_exit(fn ->
        cleanup(app_atom, "#{LibraryHandler.extensions_path()}/#{app}-#{version}")
      end)

      {:error, [%{action: :verify_checksum}]} =
        assert Installer.install(%{
                 app: app,
                 version: version,
                 type: :url,
                 path: "https://cdn.example.com/#{app}.tar.gz",
                 checksum: "deadbeef"
               })

      assert is_nil(Installer.get(:app, app))
      refute app_atom in started_apps()
    end
  end

  ###################################################################################
  ######################## (▰˘◡˘▰) Allow/deny policy (▰˘◡˘▰) ###################
  ###################################################################################
  describe "Installer allow/deny policy ===>" do
    test "a protected app cannot be installed over (mishka_installer is protected by default)" do
      {:error, [%{action: :allowlist}]} =
        assert Installer.install(%{app: "mishka_installer", version: "9.9.9", path: "whatever"})
    end

    test "a protected app cannot be uninstalled" do
      {:error, [%{action: :allowlist}]} =
        assert Installer.uninstall(%{app: "mishka_installer", version: "9.9.9", path: "p"})
    end

    test "a custom protected app (e.g. the host app) is also blocked" do
      Application.put_env(:mishka_installer, :allowlist, protected_apps: ["host_app"])
      on_exit(fn -> Application.delete_env(:mishka_installer, :allowlist) end)

      {:error, [%{action: :allowlist}]} =
        assert Installer.install(%{app: "host_app", version: "1.0.0", path: "p"})
    end

    test "a download from a host not in :url_hosts is blocked before downloading" do
      Application.put_env(:mishka_installer, :allowlist, url_hosts: ["github.com"])
      on_exit(fn -> Application.delete_env(:mishka_installer, :allowlist) end)

      {:error, [%{action: :allowlist}]} =
        assert Installer.install(%{
                 app: uniq_app("blocked_url"),
                 version: "0.1.0",
                 type: :url,
                 path: "https://evil.example.com/x.tar.gz"
               })
    end

    test "a download from a github repo not in :github_repos is blocked before downloading" do
      Application.put_env(:mishka_installer, :allowlist, github_repos: ["mishka-group/allowed"])
      on_exit(fn -> Application.delete_env(:mishka_installer, :allowlist) end)

      {:error, [%{action: :allowlist}]} =
        assert Installer.install(%{
                 app: uniq_app("blocked_repo"),
                 version: "0.1.0",
                 type: :github_tag,
                 path: "evil/repo",
                 tag: "0.1.0"
               })
    end

    test "a download from an allowed host passes the policy and installs" do
      Application.put_env(:mishka_installer, :allowlist, url_hosts: ["cdn.example.com"])

      Application.put_env(:mishka_installer, :downloader_req_options,
        plug: {Req.Test, Downloader}
      )

      app = uniq_app("allowed_url")
      app_atom = String.to_atom(app)
      version = "0.1.0"
      {tarball, ^app_atom, module} = EbinFixture.tar_fake_app(app_atom, version)
      dest = "#{LibraryHandler.extensions_path()}/#{app}-#{version}"
      stub_download(tarball)

      on_exit(fn ->
        cleanup(app_atom, dest)
        Application.delete_env(:mishka_installer, :allowlist)
      end)

      {:ok, _output} =
        assert Installer.install(%{
                 app: app,
                 version: version,
                 type: :url,
                 path: "https://cdn.example.com/#{app}.tar.gz"
               })

      assert module.hello() == :world
    end
  end

  ###################################################################################
  ########################## (▰˘◡˘▰) Helpers (▰˘◡˘▰) ##########################
  ###################################################################################
  defp uniq_app(prefix), do: "mishka_#{prefix}_#{System.unique_integer([:positive])}"

  defp fake_local_app do
    app = uniq_app("ebin_demo")
    app_atom = String.to_atom(app)
    version = "0.1.0"
    pkg = "#{LibraryHandler.extensions_path()}/#{app}-#{version}"
    File.rm_rf!(pkg)
    {^app_atom, module, _ebin} = EbinFixture.build_fake_app(pkg, app_atom, version)
    {app, app_atom, version, pkg, module}
  end

  defp started_apps, do: Enum.map(Application.started_applications(), &elem(&1, 0))

  defp stub_download(tarball) do
    Req.Test.stub(Downloader, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/gzip", nil)
      |> Plug.Conn.send_resp(200, tarball)
    end)
  end

  defp cleanup(app_atom, dir) do
    Application.stop(app_atom)
    Application.unload(app_atom)
    File.rm_rf!(dir)
  end
end
