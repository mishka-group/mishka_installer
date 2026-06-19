defmodule MishkaInstaller.Event.EventHandlerTelemetryTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{Event, EventHandler}

  @events [
    [:mishka_installer, :event, :compile],
    [:mishka_installer, :event, :synchronized]
  ]

  setup do
    System.put_env("PROJECT_PATH", File.cwd!())
    :persistent_term.put(:compile_status, "ready")
    tmp = Path.join(System.tmp_dir!(), "mishka-event-tel-#{System.unique_integer([:positive])}")

    Application.put_env(:mishka_installer, MishkaInstaller.MnesiaRepo,
      mnesia_dir: tmp,
      essential: [Event]
    )

    test_pid = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach_many(
      handler,
      @events,
      fn event, meas, meta, _ -> send(test_pid, {:telemetry, event, meas, meta}) end,
      nil
    )

    MishkaInstaller.subscribe("mnesia")
    start_supervised!(EventHandler)
    start_supervised!(MishkaInstaller.MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}

    on_exit(fn ->
      :telemetry.detach(handler)
      File.rm_rf!(tmp)
    end)

    :ok
  end

  test "emits [:event, :synchronized] once plugins start after the store is ready" do
    assert_receive {:telemetry, [:mishka_installer, :event, :synchronized], _meas, %{node: _}}
  end

  test "emits [:event, :compile] when an event module is (re)built" do
    :ok = EventHandler.do_compile("after_login_test", :start, false)

    assert_receive {:telemetry, [:mishka_installer, :event, :compile], _meas,
                    %{event: "after_login_test", result: :ok}}
  end

  test "a :cluster_recompile from another node rebuilds the event module locally" do
    event = "remote_evt_#{System.unique_integer([:positive])}"

    send(
      Process.whereis(EventHandler),
      %{status: :cluster_recompile, channel: "event", data: %{event: event, origin: :peer@nohost}}
    )

    assert_receive {:telemetry, [:mishka_installer, :event, :compile], _meas,
                    %{event: ^event, result: :ok}}
  end

  test "a :cluster_changed broadcast reconciles compiled event modules" do
    {:ok, _} =
      Event.write(%{
        name: MishkaTest.ReconcileMod,
        event: "reconcile_evt",
        extension: :mishka_installer
      })

    send(Process.whereis(EventHandler), %{status: :cluster_changed, channel: "mnesia"})

    assert_receive {:telemetry, [:mishka_installer, :event, :compile], _meas,
                    %{event: "reconcile_evt", result: :ok}}
  end
end
