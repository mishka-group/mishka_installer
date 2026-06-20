defmodule MishkaInstallerTest.Event.EventTest.AddOne do
  @moduledoc false
  def call(state), do: {:reply, Map.update(state, :n, 1, &(&1 + 1))}
end

defmodule MishkaInstallerTest.Event.EventTest.Double do
  @moduledoc false
  def call(state), do: {:reply, Map.update(state, :n, 0, &(&1 * 2))}
end

defmodule MishkaInstallerTest.Event.EventTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{Event, EventHandler, ModuleStateCompiler}
  alias MishkaInstaller.Event.Hook
  alias MishkaInstallerTest.Support.MishkaPlugin.RegisterEmailSender
  alias MishkaInstallerTest.Support.MishkaPlugin.RegisterOTPSender

  setup do
    :persistent_term.put(:compile_status, "ready")
    # Got the idea from: https://github.com/Schultzer/ecto_qlc/blob/main/test/support/data_case.ex
    tmp_dir = System.tmp_dir!()

    mnesia_dir =
      "#{Path.join(tmp_dir, "mishka-installer-#{MishkaInstaller.Helper.UUID.generate()}")}"

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

    Application.put_env(:mishka_installer, MishkaInstaller.MnesiaRepo,
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
      {:error, errors} = assert Event.write(%{})
      assert Enum.sort(Enum.map(errors, & &1.field)) == [:event, :extension, :name]

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

  ###################################################################################
  ###################### (▰˘◡˘▰) Dependency cycle (▰˘◡˘▰) #####################
  ###################################################################################
  describe "dependency cycle detection ===>" do
    test "register rejects a plugin whose dependencies cycle back to it" do
      # A depends on B (not registered yet) -> held, but no cycle.
      {:ok, a} =
        assert Event.register(RegisterEmailSender, "after_success_login", %{
                 depends: [RegisterOTPSender]
               })

      assert a.status == :held

      # B depends on A -> A <-> B, which is rejected.
      assert {:error, [%{action: :register, field: :depends}]} =
               Event.register(RegisterOTPSender, "after_success_login", %{
                 depends: [RegisterEmailSender]
               })
    end

    test "no_dependency_cycle/2 is :ok for acyclic deps and errors on a self-cycle" do
      assert Event.no_dependency_cycle(RegisterEmailSender, []) == :ok
      assert Event.no_dependency_cycle(RegisterEmailSender, [RegisterOTPSender]) == :ok

      assert {:error, _} =
               Event.no_dependency_cycle(RegisterEmailSender, [RegisterEmailSender])
    end

    test "the on_dependency_error/1 callback is injected and defaults to returning the error" do
      assert RegisterEmailSender.on_dependency_error(:boom) == :boom
    end
  end

  ###################################################################################
  ##################### (▰˘◡˘▰) Unregister robustness (▰˘◡˘▰) ##################
  ###################################################################################
  describe "unregister robustness ===>" do
    test "unregister(:name) succeeds even when the plugin process is not running" do
      {:ok, _} =
        Event.write(%{name: MishkaTest.NoProc, event: "noproc_evt", extension: :mishka_installer})

      # No GenServer was ever started for MishkaTest.NoProc.
      assert {:ok, _} = Event.unregister(:name, MishkaTest.NoProc, false)
      assert is_nil(Event.get(:name, MishkaTest.NoProc))
    end
  end

  ###################################################################################
  #################### (▰˘◡˘▰) Inaccessible plugins (▰˘◡˘▰) ###################
  ###################################################################################
  describe "inaccessible plugins ===>" do
    test "an event with a started but unloaded plugin compiles to an error stub" do
      {:ok, _} =
        assert Event.write(%{
                 name: MishkaTest.NotLoadedPlugin,
                 event: "ghost_event",
                 extension: :mishka_installer,
                 status: :started
               })

      :ok = EventHandler.do_compile("ghost_event", :start, false)

      module = ModuleStateCompiler.module_event_name("ghost_event")
      assert module.mode() == :error

      assert {:error, [%{action: :call, field: :event, plugins: [MishkaTest.NotLoadedPlugin]}]} =
               Hook.call("ghost_event", %{})
    end

    test "an event whose plugins are all loaded compiles to a runnable module" do
      {:ok, _} = assert Event.register(RegisterEmailSender, "after_success_login", %{depends: []})
      {:ok, _} = assert Event.start(:name, RegisterEmailSender, false)

      module = ModuleStateCompiler.module_event_name("after_success_login")
      assert module.mode() == :ok
      assert function_exported?(module, :call, 2)
    end
  end

  ###################################################################################
  ###################### (▰˘◡˘▰) Recompile safety (▰˘◡˘▰) #####################
  ###################################################################################
  describe "recompile safety ===>" do
    test "Hook.call never crashes while the event module is recompiled (no purge gap)" do
      {:ok, _} = assert Event.register(RegisterEmailSender, "after_success_login", %{depends: []})
      {:ok, _} = assert Event.start(:name, RegisterEmailSender, false)
      event = "after_success_login"

      reader =
        Task.async(fn ->
          Enum.each(1..1000, fn _ -> Hook.call(event, %{counter: 0}) end)
          :ok
        end)

      recompiler =
        Task.async(fn ->
          Enum.each(1..100, fn _ -> ModuleStateCompiler.purge_create([], event) end)
          :ok
        end)

      assert Task.await(reader, 15_000) == :ok
      assert Task.await(recompiler, 15_000) == :ok
    end
  end

  ###################################################################################
  ################## (▰˘◡˘▰) Dependency ordering & graph (▰˘◡˘▰) ###############
  ###################################################################################
  describe "dependency ordering (libgraph) ===>" do
    test "a plugin runs AFTER its dependency, overriding priority" do
      add_one = MishkaInstallerTest.Event.EventTest.AddOne
      double = MishkaInstallerTest.Event.EventTest.Double

      # By priority alone AddOne (1) would run before Double (2): 5 -> 6 -> 12.
      # AddOne depends on Double, so Double must run first: 5 -> 10 -> 11.
      {:ok, _} =
        Event.write(%{
          name: double,
          event: "dep_order_evt",
          extension: :mishka_installer,
          status: :started,
          priority: 2
        })

      {:ok, _} =
        Event.write(%{
          name: add_one,
          event: "dep_order_evt",
          extension: :mishka_installer,
          status: :started,
          priority: 1,
          depends: [double]
        })

      :ok = EventHandler.do_compile("dep_order_evt", :start, false)

      assert Hook.call("dep_order_evt", %{n: 5}) == %{n: 11}
    end

    test "dependency_order/1 sorts dependencies before dependents, priority breaks ties" do
      a = %{name: :a, priority: 1, depends: [:b]}
      b = %{name: :b, priority: 5, depends: []}
      c = %{name: :c, priority: 2, depends: []}

      ordered = Event.dependency_order([a, b, c]) |> Enum.map(& &1.name)
      # :b before :a (dependency); among the independents, lower priority first.
      assert Enum.find_index(ordered, &(&1 == :b)) < Enum.find_index(ordered, &(&1 == :a))
      assert ordered == [:c, :b, :a] or ordered == [:b, :c, :a]
    end

    test "connections/0 returns the libgraph dependency graph" do
      add_one = MishkaInstallerTest.Event.EventTest.AddOne
      double = MishkaInstallerTest.Event.EventTest.Double

      {:ok, _} = Event.write(%{name: double, event: "g_evt", extension: :mishka_installer})

      {:ok, _} =
        Event.write(%{
          name: add_one,
          event: "g_evt",
          extension: :mishka_installer,
          depends: [double]
        })

      graph = Event.connections()
      assert double in Graph.out_neighbors(graph, add_one)
      assert Graph.is_acyclic?(graph)
    end
  end

  ###################################################################################
  ###################### (▰˘◡˘▰) call/2 behaviour (▰˘◡˘▰) #####################
  ###################################################################################
  describe "compiled event call/2 ===>" do
    setup do
      add_one = MishkaInstallerTest.Event.EventTest.AddOne
      double = MishkaInstallerTest.Event.EventTest.Double

      # AddOne (priority 1) runs before Double (priority 2): n -> (n+1) -> *2.
      {:ok, _} =
        Event.write(%{
          name: add_one,
          event: "transform_evt",
          extension: :mishka_installer,
          status: :started,
          priority: 1
        })

      {:ok, _} =
        Event.write(%{
          name: double,
          event: "transform_evt",
          extension: :mishka_installer,
          status: :started,
          priority: 2
        })

      :ok = EventHandler.do_compile("transform_evt", :start, false)
      :ok
    end

    test "runs the plugins in priority order and transforms the data through the chain" do
      assert Hook.call("transform_evt", %{n: 5}) == %{n: 12}
    end

    test "merges :private into the result" do
      assert Hook.call("transform_evt", %{n: 5}, private: %{tag: "x"}) == %{n: 12, tag: "x"}
    end

    test ":return short-circuits and gives back the input untouched" do
      assert Hook.call("transform_evt", %{n: 5}, return: true) == %{n: 5}
    end
  end

  ###################################################################################
  ######################## (▰˘◡˘▰) Plugin profiler (▰˘◡˘▰) ####################
  ###################################################################################
  describe "plugin profiler ===>" do
    test "Hook.profile returns per-plugin timings in execution order" do
      add_one = MishkaInstallerTest.Event.EventTest.AddOne
      double = MishkaInstallerTest.Event.EventTest.Double

      {:ok, _} =
        Event.write(%{
          name: add_one,
          event: "prof_evt",
          extension: :mishka_installer,
          status: :started,
          priority: 1
        })

      {:ok, _} =
        Event.write(%{
          name: double,
          event: "prof_evt",
          extension: :mishka_installer,
          status: :started,
          priority: 2
        })

      :ok = EventHandler.do_compile("prof_evt", :start, false)

      {:ok, timings} = Hook.profile("prof_evt", %{n: 1})
      assert Enum.map(timings, & &1.plugin) == [add_one, double]
      assert Enum.all?(timings, &is_integer(&1.microseconds))
    end

    test "Hook.profile returns {:error, :not_compiled} for an event that was never compiled" do
      assert Hook.profile("never_#{System.unique_integer([:positive])}", %{}) ==
               {:error, :not_compiled}
    end
  end

  ###################################################################################
  ##################### (▰˘◡˘▰) Atomic transitions (▰˘◡˘▰) ####################
  ###################################################################################
  describe "atomic status transitions ===>" do
    test "concurrent writes to different fields of the same record don't clobber each other" do
      {:ok, rec} =
        assert Event.write(%{
                 name: MishkaTest.AtomicMod,
                 event: "atomic_evt",
                 extension: :mishka_installer
               })

      id = rec.id

      for _ <- 1..30 do
        {:ok, _} = Event.write(:id, id, %{status: :registered, priority: 100})

        t1 = Task.async(fn -> Event.write(:id, id, %{status: :stopped}) end)
        t2 = Task.async(fn -> Event.write(:id, id, %{priority: 7}) end)
        {:ok, _} = Task.await(t1)
        {:ok, _} = Task.await(t2)

        final = Event.get(id)
        assert final.status == :stopped
        assert final.priority == 7
      end
    end
  end

  ###################################################################################
  ################### (▰˘◡˘▰) Hot/warm path optimizations (▰˘◡˘▰) #############
  ###################################################################################
  describe "performance helpers ===>" do
    test "module_event_name/1 is deterministic and memoized in :persistent_term" do
      event = "cache_evt_#{System.unique_integer([:positive])}"

      m1 = ModuleStateCompiler.module_event_name(event)
      m2 = ModuleStateCompiler.module_event_name(event)

      assert is_atom(m1)
      assert m1 == m2
      # The second call is a cache hit; the mapping is stored once.
      assert :persistent_term.get({ModuleStateCompiler, :name_cache, event}) == m1
    end

    test "dirty_get/2 reads a plugin without a transaction, matching get/2" do
      assert Event.dirty_get(:name, MishkaTest.Dirty) == nil

      {:ok, _} =
        Event.write(%{name: MishkaTest.Dirty, event: "dirty_evt", extension: :mishka_installer})

      assert Event.dirty_get(:name, MishkaTest.Dirty) == Event.get(:name, MishkaTest.Dirty)
      assert Event.dirty_get(:name, MishkaTest.Dirty).name == MishkaTest.Dirty
    end
  end
end
