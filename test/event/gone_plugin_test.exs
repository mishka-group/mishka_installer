# Plugins this suite registers. `Removed` is never defined: it stands for a plugin a newer version of
# its extension no longer has.
defmodule MishkaInstallerTest.Event.GonePluginTest.Kept do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, Map.update(state, :ran, [__MODULE__], &(&1 ++ [__MODULE__]))}
end

defmodule MishkaInstallerTest.Event.GonePluginTest.Dependent do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, Map.update(state, :ran, [__MODULE__], &(&1 ++ [__MODULE__]))}
end

defmodule MishkaInstallerTest.Event.GonePluginTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias MishkaInstaller.Event.{Event, EventHandler, Hook, ModuleStateCompiler}
  alias MishkaInstallerTest.Event.GonePluginTest.{Dependent, Kept}

  @removed MishkaInstallerTest.Event.GonePluginTest.Removed
  @event "gone_plugin_evt"
  @dependent_event "gone_plugin_dependent_evt"

  setup do
    :persistent_term.put(:compile_status, "ready")
    tmp = Path.join(System.tmp_dir!(), "mishka-gone-#{System.unique_integer([:positive])}")

    Application.put_env(:mishka_installer, MishkaInstaller.MnesiaRepo,
      mnesia_dir: tmp,
      essential: [Event]
    )

    on_exit(fn ->
      for name <- [MishkaInstaller.MnesiaRepo, EventHandler] do
        pid = Process.whereis(name)

        if is_pid(pid) and Process.alive?(pid),
          do: MishkaInstallerTest.Support.ProcessHelpers.stop_if_running(name)
      end

      for event <- [@event, @dependent_event], do: ModuleStateCompiler.purge(event)
      File.rm_rf!(tmp)
    end)

    MishkaInstaller.subscribe("mnesia")
    start_supervised!(EventHandler)
    start_supervised!(MishkaInstaller.MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}

    # The handler's own boot sync — `unregister_gone/1`, then the events — is over before a test
    # writes anything it could take.
    assert_receive %{status: :event_status, channel: "mnesia", data: "ready"}

    :ok
  end

  # A started plugin of `@event` whose module its extension no longer has, one that is still there
  # beside it, and a plugin of another event that depends on the gone one.
  defp left_behind do
    {:ok, _} =
      Event.write(%{
        name: @removed,
        event: @event,
        extension: :mishka_installer,
        status: :started
      })

    {:ok, _} = Event.register(Kept, @event, %{depends: []})
    {:ok, _} = Event.start(:name, Kept, false)

    {:ok, _} =
      Event.write(%{
        name: Dependent,
        event: @dependent_event,
        extension: :mishka_installer,
        status: :started,
        depends: [@removed]
      })

    :ok = EventHandler.do_compile(@event, :start, false)
  end

  describe "gone?/1" do
    test "is true only when the extension is loaded and holds no such module" do
      assert Event.gone?(%{name: @removed, extension: :mishka_installer})

      refute Event.gone?(%{name: Event, extension: :mishka_installer})
      refute Event.gone?(%{name: Kept, extension: :mishka_installer})
      refute Event.gone?(%{name: @removed, extension: :an_extension_not_loaded_yet})
      refute Event.gone?(%{name: "not a module", extension: :mishka_installer})
    end
  end

  describe "unregister_gone/1" do
    test "unregisters a gone plugin, holds what depended on it, and its event runs the rest" do
      left_behind()

      assert Hook.call(@event, %{}, cannot_run: :cannot_run) == :cannot_run

      assert [%{name: @removed}] = Event.unregister_gone(false)

      assert is_nil(Event.get(:name, @removed))
      assert Event.get(:name, Kept).status == :started
      assert Event.get(:name, Dependent).status == :held
      assert Hook.call(@event, %{}) == %{ran: [Kept]}
    end

    test "leaves a plugin whose extension is not loaded, and its event still cannot run" do
      {:ok, _} =
        Event.write(%{
          name: @removed,
          event: @event,
          extension: :an_extension_not_loaded_yet,
          status: :started
        })

      log = capture_log(fn -> :ok = EventHandler.do_compile(@event, :start, false) end)
      assert log =~ "#{inspect(@event)} cannot run: [#{inspect(@removed)}] not loaded"

      assert Event.unregister_gone(false) == []
      assert %Event{name: @removed} = Event.get(:name, @removed)
      assert Hook.call(@event, %{}) == %{}
      assert Hook.call(@event, %{}, cannot_run: :cannot_run) == :cannot_run
    end
  end

  describe "on boot" do
    test "a gone plugin is unregistered before the events start, with a warning and telemetry" do
      left_behind()
      test_pid = self()
      handler = {__MODULE__, make_ref()}

      :telemetry.attach_many(
        handler,
        [[:mishka_installer, :event, :unregistered_gone], [:mishka_installer, :event, :compile]],
        fn [_, _, name], _measurements, metadata, _ -> send(test_pid, {name, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      log =
        capture_log(fn ->
          send(Process.whereis(EventHandler), %{status: :compile_synchronized, channel: "mnesia"})

          assert_receive {:unregistered_gone,
                          %{plugin: @removed, event: @event, extension: :mishka_installer}}

          assert_receive {:compile, %{event: @event, result: :ok}}
        end)

      assert log =~ "unregistered #{inspect(@removed)}"
      assert log =~ ":mishka_installer no longer has this module"
      assert is_nil(Event.get(:name, @removed))
      assert Hook.call(@event, %{}) == %{ran: [Kept]}
    end
  end
end
