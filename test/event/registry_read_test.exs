defmodule MishkaInstallerTest.Event.RegistryReadTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.Event
  alias MishkaInstaller.Installer.Installer
  alias MishkaInstaller.MnesiaRepo
  alias MishkaInstallerTest.Support.ProcessHelpers

  @plugin MishkaInstallerTest.Event.RegistryReadTest.Stored

  setup do
    tmp = Path.join(System.tmp_dir!(), "mishka-registry-#{System.unique_integer([:positive])}")

    Application.put_env(:mishka_installer, MnesiaRepo,
      mnesia_dir: tmp,
      essential: [Event, Installer]
    )

    on_exit(fn ->
      ProcessHelpers.stop_if_running(MnesiaRepo)
      File.rm_rf!(tmp)
    end)

    MishkaInstaller.subscribe("mnesia")
    start_supervised!(MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}

    {:ok, stored} =
      Event.write(%{
        name: @plugin,
        event: "registry_read_evt",
        extension: :mishka_installer,
        status: :started
      })

    {:ok, library} = Installer.write(%{app: "registry_read", version: "0.1.0", path: "x"})
    %{stored: stored, library: library}
  end

  test "every read answers the stored records as structs", %{stored: stored, library: library} do
    assert Event.get() == [stored]
    assert Event.get(:event, "registry_read_evt") == [stored]
    assert Event.get(:extension, :mishka_installer) == [stored]
    assert Event.get(:name, @plugin) == stored
    assert Event.get(stored.id) == stored
    assert Event.dirty_get(:name, @plugin) == stored
    assert Event.group_events() == {:ok, ["registry_read_evt"]}

    assert Installer.get() == [library]
    assert Installer.get(:app, "registry_read") == library
    assert Installer.get(library.id) == library

    assert Event.get(:event, "no_such_evt") == []
    assert Event.get(:name, MishkaInstallerTest.Event.RegistryReadTest.Missing) == nil
  end

  test "a read answers while a lifecycle write holds the record's lock", %{stored: stored} do
    test = self()

    holder =
      spawn(fn ->
        :mnesia.transaction(fn ->
          :mnesia.read(Event, stored.id, :write)
          send(test, :locked)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :locked

    assert Event.get(:name, @plugin) == stored
    assert Event.get(:event, "registry_read_evt") == [stored]
    assert Event.get() == [stored]

    ref = Process.monitor(holder)
    send(holder, :release)
    assert_receive {:DOWN, ^ref, :process, ^holder, :normal}
  end

  @tag :capture_log
  test "a read answers nothing, without exiting, while Mnesia is stopped", %{stored: stored} do
    :stopped = :mnesia.stop()

    assert Event.get() == []
    assert Event.get(:event, "registry_read_evt") == []
    assert Event.get(:name, @plugin) == nil
    assert Event.get(stored.id) == nil
    assert Event.dirty_get(:name, @plugin) == nil
    assert {:error, [%{action: :database}]} = Event.group_events()
    assert Installer.get() == []
    assert Installer.get(:app, "registry_read") == nil
  end
end
