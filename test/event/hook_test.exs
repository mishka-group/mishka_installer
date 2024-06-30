defmodule MishkaInstallerTest.Event.HookTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{Event, ModuleStateCompiler}
  alias MishkaInstallerTest.Support.MishkaPlugin.Bulk

  setup do
    :persistent_term.put(:compile_status, "ready")
    # Got the idea from: https://github.com/Schultzer/ecto_qlc/blob/main/test/support/data_case.ex
    tmp_dir = System.tmp_dir!()

    mnesia_dir =
      "#{Path.join(tmp_dir, "mishka-installer-#{MishkaDeveloperTools.Helper.UUID.generate()}")}"

    on_exit(fn ->
      pid = Process.whereis(MishkaInstaller.MnesiaRepo)
      pid1 = Process.whereis(MishkaInstaller.Event.EventHandler)

      if !is_nil(pid) and Process.alive?(pid) do
        GenServer.stop(MishkaInstaller.MnesiaRepo)
      end

      if !is_nil(pid1) and Process.alive?(pid1) do
        GenServer.stop(MishkaInstaller.Event.EventHandler)
      end
    end)

    Process.register(self(), :__mishka_installer_event_test__)

    Application.put_env(:mishka_installer, Mishka.MnesiaRepo,
      mnesia_dir: mnesia_dir,
      essential: [Event]
    )

    MishkaInstaller.subscribe("mnesia")
    MishkaInstaller.subscribe("event")
    start_supervised!(MishkaInstaller.Event.EventHandler)
    start_supervised!(MishkaInstaller.MnesiaRepo)

    assert_receive %{status: :event_status, channel: "mnesia", data: _data}

    assert_receive %{status: :synchronized, channel: "mnesia", data: _data}
    :ok
  end

  ###################################################################################
  ####################### (▰˘◡˘▰) Macro API Test (▰˘◡˘▰) ######################
  ###################################################################################
  describe "Macro API Test ===>" do
    test "Register and start a plugin by checking event creating" do
      {:ok, _pid} = assert Bulk.EventCSocial.start_link()

      assert_receive %{status: :register, data: _data}

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :purge_create, data: _data}, 3000

      module = ModuleStateCompiler.module_event_name("event_c")
      assert Code.ensure_loaded?(module)
      assert module.initialize?()
    end

    test "Start a plugin" do
      %{
        name: Bulk.EventCSocial,
        event: "event_c",
        extension: :mishka_installer,
        status: :registered
      }
      |> Event.write()

      {:ok, _pid} = assert Bulk.EventCSocial.start_link()

      {:ok, _db_plg} = assert Bulk.EventCSocial.start()

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :purge_create, data: _data}, 3000

      module = ModuleStateCompiler.module_event_name("event_c")
      assert Code.ensure_loaded?(module)
      assert module.initialize?()
    end

    test "Restart a plugin" do
      {:ok, _pid} = assert Bulk.EventCSocial.start_link()
      assert_receive %{status: :register, data: _data}

      assert_receive %{status: :start, data: _data}

      {:ok, _db_plg} = assert Bulk.EventCSocial.restart()

      assert_receive %{status: :restart, data: _data}

      assert_receive %{status: :purge_create, data: _data}, 3000

      module = ModuleStateCompiler.module_event_name("event_c")
      assert Code.ensure_loaded?(module)
      assert module.initialize?()
    end

    test "Stop a plugin" do
      {:ok, _pid} = assert Bulk.EventCSocial.start_link()
      assert_receive %{status: :register, data: _data}

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :purge_create, data: _data}, 3000

      {:ok, _db_plg} = assert Bulk.EventCSocial.stop()

      assert_receive %{status: :stop, data: _data}

      assert_receive %{status: :purge_create, data: _data}, 3000

      module = ModuleStateCompiler.module_event_name("event_c")
      assert Code.ensure_loaded?(module)
      assert module.initialize?()
      %{module: _, plugins: []} = assert module.initialize()
    end

    test "Unregister a plugin" do
      {:ok, _pid} = assert Bulk.EventCSocial.start_link()
      assert_receive %{status: :register, data: _data}

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :purge_create, data: _data}, 3000

      {:ok, _db_plg} = assert Bulk.EventCSocial.unregister()

      assert_receive %{status: :unregister, data: _data}

      assert_receive %{status: :purge_create, data: _data}, 3000

      module = ModuleStateCompiler.module_event_name("event_c")
      assert Code.ensure_loaded?(module)
      %{module: _, plugins: []} = assert module.initialize()
    end
  end
end
