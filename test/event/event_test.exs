defmodule MishkaInstallerTest.Event.EventTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{Event, ModuleStateCompiler}
  alias MishkaInstallerTest.Support.MishkaPlugin.RegisterEmailSender

  setup do
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

    Application.put_env(:mishka, Mishka.MnesiaRepo, mnesia_dir: mnesia_dir, essential: [Event])
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

      assert length(Event.ides()) == 1
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

    test "Start a plugin" do
      %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
      |> Event.write()

      {:ok, _struct} = assert Event.write(:name, RegisterEmailSender, %{depends: []})
      {:ok, struct1} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})

      {:ok, %Event{extension: :mishka_installer, status: :started, name: RegisterEmailSender}} =
        assert Event.start(:name, struct1.name)

      assert_receive %{status: :start, data: _data}

      {:error, [%{message: _msg, field: :global, action: :exist_record?}]} =
        assert Event.start(:name, RegisterEmailSender1)
    end

    test "Start all plugins of an event" do
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

      Event.start(:event, "after_login_test")

      assert_receive %{status: :start, data: _data}

      # TODO:
      # module = ModuleStateCompiler.module_event_name("after_login_test")
      # assert module.initialize?()

      # assert length(module.initialize().plugins) == 3
      module = ModuleStateCompiler.module_event_name("before_none_login_test")

      assert_raise UndefinedFunctionError, fn ->
        assert module.initialize?()
      end

      # TODO:
      # module = ModuleStateCompiler.module_event_name("before_login_test")
      # assert module.initialize?()
    end

    test "Start all events" do
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

      # TODO: initialize and test event state module
    end

    test "Restart a plugin" do
      %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
      |> Event.write()

      {:ok, _data} = Event.restart(:name, RegisterEmailSender)

      {:ok, _struct} =
        assert Event.write(:name, RegisterEmailSender, %{depends: [RegisterEmailSender1]})

      {:error, _error} = assert Event.restart(:name, RegisterEmailSender)
      {:error, _error1} = assert Event.restart(:name, RegisterEmailSender1)

      {:ok, _struct1} = assert Event.write(:name, RegisterEmailSender, %{depends: []})
      {:ok, _struct2} = assert Event.write(:name, RegisterEmailSender, %{status: :registered})
    end

    test "Restart an event" do
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

      {:ok, _data} = Event.restart(:event, "after_login_test")

      assert_receive %{status: :restart, data: _data}

      {:ok, _data} = Event.restart(:event, "before_login_test")

      assert_receive %{status: :restart, data: _data}
    end

    test "Restart all events" do
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

      assert_receive %{status: :restart, data: _data}
    end

    test "Stop a plugin" do
      create = fn ->
        %{name: RegisterEmailSender, event: "after_success_login", extension: :mishka_installer}
        |> Event.write()
      end

      {:ok, data} = assert create.()

      {:ok, %Event{extension: :mishka_installer, status: :stopped}} =
        assert Event.stop(:name, data.name)

      {:error, _errors} = assert Event.stop(:name, RegisterEmailSender1)

      {:error, _errors1} = assert Event.stop(:name, RegisterEmailSender)
    end

    test "Stop an event" do
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

      # TODO: initialize and test event state module
      {:ok, _data} = assert Event.stop(:event, "after_login_test")

      assert_receive %{status: :stop, data: _data}

      {:ok, _data} = assert Event.stop(:event, "before_login_test")

      assert_receive %{status: :stop, data: _data}

      # TODO: initialize and test event state module
    end

    test "Stop all events" do
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

      # TODO: initialize and test event state module
      {:ok, _data} = assert Event.stop()

      assert_receive %{status: :stop, data: _data}

      assert_receive %{status: :stop, data: _data}

      # TODO: initialize and test event state module
    end

    test "Unregister a plugin" do
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

      {:ok, _unregister_data} = assert Event.unregister(:name, RegisterEmailSender)

      assert_receive %{status: :unregister, data: _data}

      assert !Process.alive?(pid)

      assert is_nil(Event.get(:name, RegisterEmailSender))

      # TODO: initialize and test event state module
    end

    test "Unregister an events" do
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

      {:ok, _data} = assert Event.unregister(:event, struct1.event)

      assert_receive %{status: :unregister, data: _data}

      assert !Process.alive?(pid)

      assert is_nil(Event.get(:name, struct1.name))
      # TODO: initialize and test event state module
    end

    test "Unregister all events" do
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

      {:ok, _data} = assert Event.unregister()

      assert_receive %{status: :unregister, data: _data}

      assert !Process.alive?(pid)

      assert is_nil(Event.get(:name, struct1.name))
      # TODO: initialize and test event state module
    end
  end
end
