# Plain modules exercising every health_check/0 return variant (no GenServer needed).
defmodule MishkaInstallerTest.Event.HealthTest.HealthyProbe do
  @moduledoc false
  def health_check(), do: :ok
end

defmodule MishkaInstallerTest.Event.HealthTest.DegradedProbe do
  @moduledoc false
  def health_check(), do: {:degraded, "upstream slow"}
end

defmodule MishkaInstallerTest.Event.HealthTest.ErrorProbe do
  @moduledoc false
  def health_check(), do: {:error, "db unreachable"}
end

defmodule MishkaInstallerTest.Event.HealthTest.CrashProbe do
  @moduledoc false
  def health_check(), do: raise("boom")
end

defmodule MishkaInstallerTest.Event.HealthTest.SlowProbe do
  @moduledoc false
  def health_check(), do: Process.sleep(5_000)
end

defmodule MishkaInstallerTest.Event.HealthTest.WeirdProbe do
  @moduledoc false
  def health_check(), do: :not_a_valid_return
end

defmodule MishkaInstallerTest.Event.HealthTest.NoProbe do
  @moduledoc false
  def hello(), do: :ok
end

# Real Hook plugins (GenServers) for the integration reports.
defmodule MishkaInstallerTest.Event.HealthTest.OkPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "health_evt"
  @impl true
  def call(state), do: {:reply, state}
end

defmodule MishkaInstallerTest.Event.HealthTest.SickPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "health_evt"
  @impl true
  def call(state), do: {:reply, state}
  @impl true
  def health_check(), do: {:error, "unhealthy"}
end

# A realistic "after login" pipeline: two plugins that actually transform the data, and whose
# health reflects a LIVE runtime condition (a toggle standing in for an external service).
defmodule MishkaInstallerTest.Event.HealthTest.AuditPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "login_flow", initial: %{priority: 1}
  @impl true
  def call(state), do: {:reply, Map.put(state, :audited, true)}
end

defmodule MishkaInstallerTest.Event.HealthTest.NotifyPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "login_flow", initial: %{priority: 2}
  @impl true
  def call(state), do: {:reply, Map.put(state, :notified, true)}

  @impl true
  def health_check() do
    if :persistent_term.get({:health_demo, :service_up}, true),
      do: :ok,
      else: {:error, "notification service down"}
  end
end

defmodule MishkaInstaller.Event.HealthTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{Event, EventHandler, Hook}

  alias MishkaInstaller.Event.ModuleStateCompiler

  alias MishkaInstallerTest.Event.HealthTest.{
    HealthyProbe,
    DegradedProbe,
    ErrorProbe,
    CrashProbe,
    SlowProbe,
    WeirdProbe,
    NoProbe,
    OkPlugin,
    SickPlugin,
    AuditPlugin,
    NotifyPlugin
  }

  setup do
    :persistent_term.put(:compile_status, "ready")
    tmp = Path.join(System.tmp_dir!(), "mishka-health-#{System.unique_integer([:positive])}")

    Application.put_env(:mishka_installer, MishkaInstaller.MnesiaRepo,
      mnesia_dir: tmp,
      essential: [Event]
    )

    on_exit(fn ->
      for name <- [MishkaInstaller.MnesiaRepo, EventHandler] do
        pid = Process.whereis(name)
        if is_pid(pid) and Process.alive?(pid), do: GenServer.stop(name)
      end

      File.rm_rf!(tmp)
    end)

    MishkaInstaller.subscribe("mnesia")
    MishkaInstaller.subscribe("event")
    start_supervised!(EventHandler)
    start_supervised!(MishkaInstaller.MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}, 2000

    :ok
  end

  describe "run_health/2 — every variant ===>" do
    test ":ok / {:degraded, _} / {:error, _} pass through" do
      assert Hook.run_health(HealthyProbe, 1000) == :ok
      assert Hook.run_health(DegradedProbe, 1000) == {:degraded, "upstream slow"}
      assert Hook.run_health(ErrorProbe, 1000) == {:error, "db unreachable"}
    end

    test "a raising probe becomes {:error, {:raised, _}}" do
      assert {:error, {:raised, %RuntimeError{}}} = Hook.run_health(CrashProbe, 1000)
    end

    test "a hanging probe is killed at the timeout and becomes {:error, :timeout}" do
      assert Hook.run_health(SlowProbe, 100) == {:error, :timeout}
    end

    test "a non-conforming return becomes {:error, {:bad_return, _}}" do
      assert Hook.run_health(WeirdProbe, 1000) == {:error, {:bad_return, :not_a_valid_return}}
    end

    test "a module without health_check/0 becomes {:error, :no_health_check}" do
      assert Hook.run_health(NoProbe, 1000) == {:error, :no_health_check}
    end

    test "running a probe leaves no stray messages in the caller's mailbox" do
      assert Hook.run_health(SlowProbe, 50) == {:error, :timeout}
      refute_receive {:DOWN, _, _, _, _}, 100
    end
  end

  describe "plugin_health/1 ===>" do
    test "a non-running module reports alive?/callable? false with its probe" do
      report = Hook.plugin_health(DegradedProbe)
      assert report.alive? == false
      assert report.callable? == false
      assert report.probe == {:degraded, "upstream slow"}
      assert report.healthy? == false
    end

    test "a started, loaded plugin with an :ok probe is healthy" do
      start_supervised!(OkPlugin)
      assert_receive %{status: :register}, 2000
      eventually(fn -> started?(OkPlugin) end)

      report = Hook.plugin_health(OkPlugin)
      assert report.alive? == true
      assert report.callable? == true
      assert report.status in [:started, :restarted]
      assert report.probe == :ok
      assert report.healthy? == true
    end
  end

  describe "event_health/1 ===>" do
    test "an uncompiled event reports compiled? false and is unhealthy" do
      report = Hook.event_health("never_compiled_evt")
      assert report.compiled? == false
      assert report.plugins == []
      assert report.healthy? == false
    end

    test "aggregates each plugin's health and the overall verdict" do
      start_supervised!(OkPlugin)
      start_supervised!(SickPlugin)
      eventually(fn -> started?(OkPlugin) and started?(SickPlugin) end)

      # Force a synchronous (re)compile so the chain reflects both started plugins.
      :ok = EventHandler.do_compile("health_evt", :start, false)

      report = Hook.event_health("health_evt")
      assert report.compiled? == true
      assert report.mode == :ok
      assert report.plugin_count == 2

      by_name = Map.new(report.plugins, &{&1.plugin, &1})
      assert by_name[OkPlugin].healthy? == true
      assert by_name[OkPlugin].probe == :ok
      assert by_name[SickPlugin].healthy? == false
      assert by_name[SickPlugin].probe == {:error, "unhealthy"}

      # One sick plugin makes the whole event unhealthy.
      assert report.healthy? == false
    end
  end

  describe "real-world event: working pipeline + LIVE health ===>" do
    setup do
      :persistent_term.put({:health_demo, :service_up}, true)
      on_exit(fn -> :persistent_term.erase({:health_demo, :service_up}) end)
      :ok
    end

    test "two real plugins run the event, and health tracks a live runtime condition" do
      # Start the plugins the normal way — each registers, starts, and (auto)compiles the event.
      # Nothing here is forced: we just wait for the natural flow to settle.
      start_supervised!(AuditPlugin)
      start_supervised!(NotifyPlugin)
      eventually(fn -> compiled_with?("login_flow", 2) end)

      # 1. The real plugin chain runs and actually transforms the data.
      assert Hook.call("login_flow", %{user: 7}) == %{user: 7, audited: true, notified: true}

      # 2. With the service up, every plugin probes healthy -> the event is healthy.
      up = Hook.event_health("login_flow")
      assert up.healthy? == true
      assert Enum.all?(up.plugins, & &1.healthy?)

      # 3. A real condition changes at runtime: the notification service goes down.
      :persistent_term.put({:health_demo, :service_up}, false)

      down = Hook.event_health("login_flow")
      notify = Enum.find(down.plugins, &(&1.plugin == NotifyPlugin))
      assert notify.probe == {:error, "notification service down"}
      assert notify.healthy? == false
      # AuditPlugin (no override -> default :ok) stays healthy; the event as a whole does not.
      assert Enum.find(down.plugins, &(&1.plugin == AuditPlugin)).healthy? == true
      assert down.healthy? == false

      # 4. Health is observability, not a gate: the event still runs while degraded.
      assert Hook.call("login_flow", %{user: 8}) == %{user: 8, audited: true, notified: true}

      # 5. Recovery is live too: bring the service back and the event is healthy again.
      :persistent_term.put({:health_demo, :service_up}, true)
      assert Hook.event_health("login_flow").healthy? == true
    end
  end

  defp compiled_with?(event, count) do
    module = ModuleStateCompiler.module_event_name(event)

    Code.ensure_loaded?(module) and function_exported?(module, :initialize, 0) and
      length(module.initialize().plugins) == count
  end

  defp started?(mod) do
    case Event.get(:name, mod) do
      %{status: status} -> status in [:started, :restarted]
      _ -> false
    end
  end

  defp eventually(fun, tries \\ 100)
  defp eventually(_fun, 0), do: flunk("condition was never met")

  defp eventually(fun, tries),
    do:
      if(fun.(),
        do: :ok,
        else:
          (
            Process.sleep(20)
            eventually(fun, tries - 1)
          )
      )
end
