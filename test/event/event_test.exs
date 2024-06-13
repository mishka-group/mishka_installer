defmodule MishkaInstallerTest.Event.EventTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.Event

  setup do
    tmp_dir = System.tmp_dir!()

    mnesia_dir =
      "#{Path.join(tmp_dir, "mishka-installer-#{MishkaDeveloperTools.Helper.UUID.generate()}")}"

    on_exit(fn ->
      pid = Process.whereis(MishkaInstaller.MnesiaRepo)

      if !is_nil(pid) and Process.alive?(pid) do
        GenServer.stop(MishkaInstaller.MnesiaRepo)
      end
    end)

    Process.register(self(), :__mishka_installer_event_test__)

    Application.put_env(:mishka, Mishka.MnesiaRepo, mnesia_dir: mnesia_dir, essential: [Event])
    MishkaInstaller.subscribe("mnesia")
    start_supervised!(MishkaInstaller.MnesiaRepo)

    assert_receive %{status: :started, channel: "mnesia", data: _data}
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
end
