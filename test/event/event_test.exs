defmodule MishkaInstallerTest.Event.EventTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{Event, ModuleStateCompiler}
  alias MishkaInstallerTest.Support.MishkaPlugin.RegisterEmailSender

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
  ########################## (▰˘◡˘▰) QueryTest (▰˘◡˘▰) ########################
  ###################################################################################
  describe "Event Table CRUD QueryTest ===>" do
    test "Create a Plugin record" do
      {:error, %{message: _msg, fields: [:extension, :event, :name]}} = assert Event.write(%{})

      create = fn ->
        %{name: MishkaTest.Email, event: "after_login_test", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, %Event{status: :registered, event: "after_login_test", name: MishkaTest.Email}} =
        assert create.()
    end

    test "Read a Plugin/Plugins records" do
      assert Event.get() == []

      %{name: MishkaTest.Email, event: "after_login_test", extension: :mishka_installer}
      |> Event.write()

      assert Event.get() != []
      assert !is_nil(Event.get(:name, MishkaTest.Email))
      assert :mishka_installer = List.first(Event.get(:event, "after_login_test")).extension
      assert is_nil(Event.get(:name, MishkaTest.Email1))
      assert [] = Event.get(:event, "after_login_test1")
      get_data = Event.get() |> List.first()
      assert !is_nil(Event.get(get_data.id))
    end

    test "Update a Plugin record" do
      %{name: MishkaTest.Email, event: "after_login_test", extension: :mishka_installer}
      |> Event.write()

      get_data = Event.get() |> List.first()
      {:ok, struct} = assert Event.write({:root, Map.merge(get_data, %{priority: 50}), :edit})
      assert struct.priority == 50
      get_data1 = Event.get() |> List.first()
      assert get_data1.id == get_data.id
      {:ok, struct} = assert Event.write(:id, get_data.id, %{priority: 67})
      assert Event.get(struct.id).priority == 67
    end

    test "All keys of plugins Record" do
      %{name: MishkaTest.Email, event: "after_login_test", extension: :mishka_installer}
      |> Event.write()

      assert length(Event.ids()) == 1
    end

    test "Unique? plugin Record by name" do
      %{name: MishkaTest.Email, event: "after_login_test", extension: :mishka_installer}
      |> Event.write()

      assert !is_nil(Event.get(:name, MishkaTest.Email))
      assert is_nil(Event.get(:name, MishkaTest.Email1))
    end

    test "Delete plugin Record" do
      %{name: MishkaTest.Email, event: "after_login_test", extension: :mishka_installer}
      |> Event.write()

      assert Event.get() != []
      {:ok, _data} = Event.delete(:name, MishkaTest.Email)
      assert Event.get() == []
    end

    test "Drop all plugins records" do
      %{name: MishkaTest.Email, event: "after_login_test", extension: :mishka_installer}
      |> Event.write()

      assert Event.get() != []
      {:ok, :atomic} = assert Event.drop()
      assert Event.get() == []
    end
  end

  ###################################################################################
  ######################## (▰˘◡˘▰) FunctionsTest (▰˘◡˘▰) ######################
  ###################################################################################
  describe "Event Module FunctionsTest ===>" do
    test "Register a plugin" do
      {:ok, %Event{extension: :mishka_installer, status: :registered, name: RegisterEmailSender}} =
        assert Event.register(RegisterEmailSender, "after_success_login", %{})

      {:error, [%{message: _msg, field: :global, action: :ensure_loaded}]} =
        assert Event.register(RegisterEmailSender1, "after_success_login", %{})

      Event.drop()

      {:ok, data} =
        assert Event.register(RegisterEmailSender, "after_success_login", %{
                 depends: [RegisterEmailSender1]
               })

      assert data.status == :held
    end

    test "Start a plugin - queue true" do
      %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
      |> Event.write()

      {:ok, _struct} = assert Event.write(:name, RegisterEmailSender, %{depends: []})
      {:ok, struct1} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})

      {:ok, %Event{extension: :mishka_installer, status: :started, name: RegisterEmailSender}} =
        assert Event.start(:name, struct1.name, true)

      assert_receive %{status: :start, data: _data}

      {:error, [%{message: _msg, field: :global, action: :exist_record?}]} =
        assert Event.start(:name, RegisterEmailSender1, true)
    end

    test "Start a plugin - queue false" do
      %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
      |> Event.write()

      {:ok, _struct} = assert Event.write(:name, RegisterEmailSender, %{depends: []})
      {:ok, struct1} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})

      {:ok, %Event{extension: :mishka_installer, status: :started, name: RegisterEmailSender}} =
        assert Event.start(:name, struct1.name, false)

      {:error, [%{message: _msg, field: :global, action: :exist_record?}]} =
        assert Event.start(:name, RegisterEmailSender1, false)
    end

    test "Start all plugins of an event - queue true" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      Event.start(:event, "after_login_test", true)

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      module = ModuleStateCompiler.module_event_name("after_login_test")
      assert module.initialize?()

      assert length(module.initialize().plugins) == 3

      Event.start(:event, "before_login_test", true)

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      module = ModuleStateCompiler.module_event_name("before_login_test")
      assert module.initialize?()

      module = ModuleStateCompiler.module_event_name("before_none_login_test")

      assert_raise UndefinedFunctionError, fn ->
        assert module.initialize?()
      end
    end

    test "Start all plugins of an event - queue false" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      Event.start(:event, "after_login_test", false)

      module = ModuleStateCompiler.module_event_name("after_login_test")
      assert module.initialize?()

      assert length(module.initialize().plugins) == 3

      Event.start(:event, "before_login_test", false)

      module = ModuleStateCompiler.module_event_name("before_login_test")
      assert module.initialize?()

      module = ModuleStateCompiler.module_event_name("before_none_login_test")

      assert_raise UndefinedFunctionError, fn ->
        assert module.initialize?()
      end
    end

    test "Start all events - queue true" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start()

      assert_receive %{status: :start, data: _data}, 3000

      assert_receive %{status: :start, data: _data}, 3000

      assert_receive %{status: :purge_create, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      module = ModuleStateCompiler.module_event_name("after_login_test")
      assert module.initialize?()

      module = ModuleStateCompiler.module_event_name("before_login_test")
      assert module.initialize?()
    end

    test "Start all events - queue false" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start(false)

      module = ModuleStateCompiler.module_event_name("after_login_test")
      assert module.initialize?()

      module = ModuleStateCompiler.module_event_name("before_login_test")
      assert module.initialize?()
    end

    test "Restart a plugin - queue true" do
      %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
      |> Event.write()

      {:ok, _data} = Event.restart(:name, RegisterEmailSender, true)

      assert_receive %{status: :restart, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      {:ok, _struct} =
        assert Event.write(:name, RegisterEmailSender, %{depends: [RegisterEmailSender1]})

      {:error, _error1} = assert Event.restart(:name, RegisterEmailSender1, true)

      {:error, _error} = assert Event.restart(:name, RegisterEmailSender, true)
    end

    test "Restart a plugin - queue false" do
      %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
      |> Event.write()

      {:ok, _data} = Event.restart(:name, RegisterEmailSender, false)

      {:ok, _struct} =
        assert Event.write(:name, RegisterEmailSender, %{depends: [RegisterEmailSender1]})

      {:error, _error1} = assert Event.restart(:name, RegisterEmailSender1, false)

      {:error, _error} = assert Event.restart(:name, RegisterEmailSender, false)
    end

    test "Restart an event - queue true" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start()

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :start, data: _data}

      {:ok, _data} = Event.restart(:event, "after_login_test", true)

      assert_receive %{status: :restart, data: _data}

      {:ok, _data} = Event.restart(:event, "before_login_test", true)

      assert_receive %{status: :restart, data: _data}
    end

    test "Restart an event - queue false" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start(false)

      {:ok, _data} = Event.restart(:event, "after_login_test", false)

      {:ok, _data} = Event.restart(:event, "before_login_test", false)
    end

    test "Restart all events - queue true" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start()

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :start, data: _data}

      {:ok, _data} = Event.restart()

      assert_receive %{status: :restart, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      assert_receive %{status: :restart, data: _data}
    end

    test "Restart all events - queue false" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start(false)
      {:ok, _data} = Event.restart(false)
    end

    test "Stop a plugin - queue true" do
      create = fn ->
        %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, data} = assert create.()

      {:ok, %Event{extension: :mishka_installer, status: :stopped}} =
        assert Event.stop(:name, data.name, true)

      {:error, _errors} = assert Event.stop(:name, RegisterEmailSender1, true)

      {:error, _errors1} = assert Event.stop(:name, RegisterEmailSender, true)
    end

    test "Stop a plugin - queue false" do
      create = fn ->
        %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, data} = assert create.()

      {:ok, %Event{extension: :mishka_installer, status: :stopped}} =
        assert Event.stop(:name, data.name, false)

      {:error, _errors} = assert Event.stop(:name, RegisterEmailSender1, false)

      {:error, _errors1} = assert Event.stop(:name, RegisterEmailSender, false)
    end

    test "Stop an event - queue true" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start()

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      module = ModuleStateCompiler.module_event_name("after_login_test")
      assert module.initialize?()

      module = ModuleStateCompiler.module_event_name("before_login_test")
      assert module.initialize?()

      {:ok, _data} = assert Event.stop(:event, "after_login_test", true)

      assert_receive %{status: :stop, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      module = ModuleStateCompiler.module_event_name("after_login_test")

      %{module: _, plugins: []} = assert module.initialize()

      {:ok, _data} = assert Event.stop(:event, "before_login_test", true)

      assert_receive %{status: :stop, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      module = ModuleStateCompiler.module_event_name("before_login_test")

      %{module: _, plugins: []} = assert module.initialize()
    end

    test "Stop an event - queue false" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start(false)

      module = ModuleStateCompiler.module_event_name("after_login_test")
      assert module.initialize?()

      module = ModuleStateCompiler.module_event_name("before_login_test")
      assert module.initialize?()

      {:ok, _data} = assert Event.stop(:event, "after_login_test", false)

      module = ModuleStateCompiler.module_event_name("after_login_test")

      %{module: _, plugins: []} = assert module.initialize()

      {:ok, _data} = assert Event.stop(:event, "before_login_test", false)

      module = ModuleStateCompiler.module_event_name("before_login_test")

      %{module: _, plugins: []} = assert module.initialize()
    end

    test "Stop all events - queue true" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start()

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :start, data: _data}

      assert_receive %{status: :purge_create, data: _data}, 3000

      assert_receive %{status: :purge_create, data: _data}, 3000

      module = ModuleStateCompiler.module_event_name("after_login_test")

      %{module: _, plugins: plugins} = assert module.initialize()

      assert length(plugins) > 0

      module = ModuleStateCompiler.module_event_name("before_login_test")

      %{module: _, plugins: plugins} = assert module.initialize()

      assert length(plugins) > 0

      {:ok, _data} = assert Event.stop()

      assert_receive %{status: :stop, data: _data}

      assert_receive %{status: :stop, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      assert_receive %{status: :purge_create, data: _data}

      module = ModuleStateCompiler.module_event_name("after_login_test")
      %{module: _, plugins: []} = assert module.initialize()

      module = ModuleStateCompiler.module_event_name("before_login_test")
      %{module: _, plugins: []} = assert module.initialize()
    end

    test "Stop all events - queue false" do
      create = fn name, status, deps, event, priority ->
        %{name: name, extension: :mishka_installer, depends: deps, priority: priority}
        |> Map.put(:event, event)
        |> Map.put(:status, status)
        |> Event.write()
      end

      deps = [MishkaPluginTest.Email1, MishkaPluginTest.Email2, MishkaPluginTest.Email3]

      create.(MishkaPluginTest.Email, :registered, deps, "after_login_test", 100)
      create.(MishkaPluginTest.Email1, :started, [], "after_login_test", 60)
      create.(MishkaPluginTest.Email2, :started, [], "after_login_test", 50)
      create.(MishkaPluginTest.Email3, :started, [], "before_login_test", 10)

      {:ok, _sorted_events} = assert Event.start(false)

      module = ModuleStateCompiler.module_event_name("after_login_test")

      %{module: _, plugins: plugins} = assert module.initialize()

      assert length(plugins) > 0

      module = ModuleStateCompiler.module_event_name("before_login_test")

      %{module: _, plugins: plugins} = assert module.initialize()

      assert length(plugins) > 0

      {:ok, _data} = assert Event.stop(false)

      module = ModuleStateCompiler.module_event_name("after_login_test")
      %{module: _, plugins: []} = assert module.initialize()

      module = ModuleStateCompiler.module_event_name("before_login_test")
      %{module: _, plugins: []} = assert module.initialize()
    end

    test "Unregister a plugin - queue true" do
      create = fn ->
        %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, _data} = assert create.()

      {:ok, _struct} = assert Event.write(:name, RegisterEmailSender, %{depends: []})

      {:ok, _struct1} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})

      start_supervised!(RegisterEmailSender)

      assert_receive %{status: :register, data: _data}

      pid = Process.whereis(RegisterEmailSender)

      assert Process.alive?(pid)

      {:ok, _unregister_data} = assert Event.unregister(:name, RegisterEmailSender, true)

      assert_receive %{status: :unregister, data: _data}, 3000
    end

    test "Unregister a plugin - queue false" do
      create = fn ->
        %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, _data} = assert create.()

      {:ok, _struct} = assert Event.write(:name, RegisterEmailSender, %{depends: []})

      {:ok, _struct1} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})

      start_supervised!(RegisterEmailSender)

      assert_receive %{status: :register, data: _data}

      pid = Process.whereis(RegisterEmailSender)

      assert Process.alive?(pid)

      {:ok, _unregister_data} = assert Event.unregister(:name, RegisterEmailSender, false)

      assert !Process.alive?(pid)

      assert is_nil(Event.get(:name, RegisterEmailSender))

      module = ModuleStateCompiler.module_event_name("after_success_login")
      %{module: _, plugins: []} = assert module.initialize()
    end

    test "Unregister an events - queue true" do
      create = fn ->
        %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, data} = assert create.()

      {:ok, _struct} = assert Event.write(:name, RegisterEmailSender, %{depends: []})

      {:ok, struct1} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})

      start_supervised!(data.name)

      assert_receive %{status: :register, data: _data}

      pid = Process.whereis(data.name)

      assert Process.alive?(pid)

      {:ok, _data} = assert Event.unregister(:event, struct1.event, true)

      assert_receive %{status: :unregister, data: _data}

      assert !Process.alive?(pid)

      assert is_nil(Event.get(:name, struct1.name))
    end

    test "Unregister an events - queue false" do
      create = fn ->
        %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, data} = assert create.()

      {:ok, _struct} = assert Event.write(:name, RegisterEmailSender, %{depends: []})

      {:ok, struct1} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})

      start_supervised!(data.name)

      assert_receive %{status: :register, data: _data}

      pid = Process.whereis(data.name)

      assert Process.alive?(pid)

      {:ok, _data} = assert Event.unregister(:event, struct1.event, false)

      assert !Process.alive?(pid)

      assert is_nil(Event.get(:name, struct1.name))
    end

    test "Unregister all events - queue true" do
      create = fn ->
        %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, data} = assert create.()

      {:ok, _struct} = assert Event.write(:name, RegisterEmailSender, %{depends: []})

      {:ok, _struct1} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})

      start_supervised!(data.name)

      assert_receive %{status: :register, data: _data}

      pid = Process.whereis(data.name)

      assert Process.alive?(pid)

      {:ok, _data} = assert Event.unregister()

      assert_receive %{status: :unregister, data: _data}

      assert !Process.alive?(pid)

      assert is_nil(Event.get(:name, RegisterEmailSender))
    end

    test "Unregister all events - queue false" do
      create = fn ->
        %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, data} = assert create.()

      {:ok, _struct} = assert Event.write(:name, RegisterEmailSender, %{depends: []})

      {:ok, _struct1} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})

      start_supervised!(data.name)

      assert_receive %{status: :register, data: _data}

      pid = Process.whereis(data.name)

      assert Process.alive?(pid)

      {:ok, _data} = assert Event.unregister(false)

      assert !Process.alive?(pid)

      assert is_nil(Event.get(:name, RegisterEmailSender))
    end
  end
end
