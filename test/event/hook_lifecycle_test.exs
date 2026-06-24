# Real Hook plugins (GenServers) exercising the lifecycle / dependency / profile / call! paths.
defmodule MishkaInstallerTest.Event.HookTest.IndependentPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "auto_start_evt", initial: %{priority: 1}
  @impl true
  def call(state), do: {:reply, Map.put(state, :independent_ran, true)}
end

defmodule MishkaInstallerTest.Event.HookTest.DependentPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook,
    event: "auto_start_evt",
    initial: %{depends: [MishkaInstallerTest.Event.HookTest.IndependentPlugin], priority: 2}

  @impl true
  def call(state), do: {:reply, Map.put(state, :dependent_ran, true)}
end

defmodule MishkaInstallerTest.Event.HookTest.ProfileNormal do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "profile_raise_evt", initial: %{priority: 1}
  @impl true
  def call(state), do: {:reply, state}
end

defmodule MishkaInstallerTest.Event.HookTest.ProfileRaiser do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "profile_raise_evt", initial: %{priority: 2}
  @impl true
  def call(_state), do: raise("profile boom")
end

defmodule MishkaInstallerTest.Event.HookTest.ReEventPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "re_event_evt"
  @impl true
  def call(state), do: {:reply, state}
end

defmodule MishkaInstallerTest.Event.HookTest.CallBangPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "callbang_evt"
  @impl true
  def call(state), do: {:reply, Map.put(state, :ran, true)}
end

defmodule MishkaInstallerTest.Event.HookTest.RetryPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "retry_evt"
  @impl true
  def call(state), do: {:reply, state}
end

defmodule MishkaInstallerTest.Event.HookTest.CyclicB do
  @moduledoc false
  use MishkaInstaller.Event.Hook,
    event: "cyclic_evt",
    initial: %{depends: [MishkaInstallerTest.Event.HookTest.CyclicA]}

  @impl true
  def call(state), do: {:reply, state}

  @impl true
  def on_dependency_error(error) do
    :persistent_term.put({:hook_test, :dep_error}, error)
    error
  end
end

defmodule MishkaInstallerTest.Event.HookTest.CyclicA do
  @moduledoc false
  use MishkaInstaller.Event.Hook,
    event: "cyclic_evt",
    initial: %{depends: [MishkaInstallerTest.Event.HookTest.CyclicB]}

  @impl true
  def call(state), do: {:reply, state}
end

defmodule MishkaInstaller.Event.HookTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{Event, EventHandler, Hook}

  alias MishkaInstallerTest.Event.HookTest.{
    IndependentPlugin,
    DependentPlugin,
    ProfileNormal,
    ProfileRaiser,
    ReEventPlugin,
    CallBangPlugin,
    RetryPlugin,
    CyclicA,
    CyclicB
  }

  setup do
    :persistent_term.put(:compile_status, "ready")
    tmp = Path.join(System.tmp_dir!(), "mishka-hook-#{System.unique_integer([:positive])}")

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

  describe "dependency resolution (auto-start) ===>" do
    test "a :held plugin auto-starts when the dependency it waits on activates" do
      # Dependent registers first -> :held, because IndependentPlugin isn't active yet.
      start_supervised!(DependentPlugin)
      eventually(fn -> status(DependentPlugin) == :held end)

      # Activating the dependency broadcasts its record; the held plugin re-evaluates and restarts.
      start_supervised!(IndependentPlugin)
      eventually(fn -> status(DependentPlugin) in [:restarted, :started] end)

      # Both now run in the compiled chain.
      :ok = EventHandler.do_compile("auto_start_evt", :start, false)
      result = Hook.call("auto_start_evt", %{})
      assert result.independent_ran == true
      assert result.dependent_ran == true
    end
  end

  describe "profile/2 ===>" do
    test "a plugin that raises is reported with 0 µs and never aborts the profile" do
      start_supervised!(ProfileNormal)
      start_supervised!(ProfileRaiser)

      eventually(fn ->
        status(ProfileNormal) == :started and status(ProfileRaiser) == :started
      end)

      :ok = EventHandler.do_compile("profile_raise_evt", :start, false)

      {:ok, timings} = Hook.profile("profile_raise_evt", %{x: 1})

      by = Map.new(timings, &{&1.plugin, &1.microseconds})
      assert is_integer(by[ProfileNormal])
      assert by[ProfileRaiser] == 0
    end
  end

  describe "call!/3 ===>" do
    test "runs the compiled event directly" do
      start_supervised!(CallBangPlugin)
      eventually(fn -> status(CallBangPlugin) == :started end)
      :ok = EventHandler.do_compile("callbang_evt", :start, false)

      assert Hook.call!("callbang_evt", %{}) == %{ran: true}
    end

    test "raises for an event that was never compiled (no graceful fallback like call/3)" do
      event = "never_#{System.unique_integer([:positive])}"
      assert_raise UndefinedFunctionError, fn -> Hook.call!(event, %{}) end
      # call/3 stays graceful on the same event.
      assert Hook.call(event, %{a: 1}) == %{a: 1}
    end
  end

  describe ":re_event with a deleted record ===>" do
    test "leaves the plugin state unchanged and does not crash" do
      start_supervised!(ReEventPlugin)
      eventually(fn -> status(ReEventPlugin) == :started end)
      before = Keyword.get(ReEventPlugin.get(), :status)

      {:ok, _} = Event.delete(:name, ReEventPlugin)
      send(ReEventPlugin, %{status: :re_event, channel: "event", data: %{}})

      # still alive, status unchanged (the nil-record branch).
      assert Process.alive?(Process.whereis(ReEventPlugin))
      assert Keyword.get(ReEventPlugin.get(), :status) == before
    end
  end

  describe "after_compile guards ===>" do
    test "a plugin with neither call/1 nor call/2 raises at compile time" do
      assert_raise RuntimeError, ~r/call\/1 or call\/2/, fn ->
        Code.eval_string("""
        defmodule MishkaTmp.NoCallPlugin do
          use MishkaInstaller.Event.Hook, event: "tmp_evt"
        end
        """)
      end
    end

    test "a plugin defining only call/2 compiles without raising" do
      Code.eval_string("""
      defmodule MishkaTmp.Call2OnlyPlugin do
        use MishkaInstaller.Event.Hook, event: "tmp_call2_evt"
        @impl true
        def call(state, _meta), do: {:reply, state}
      end
      """)

      assert function_exported?(MishkaTmp.Call2OnlyPlugin, :call, 2)
    end

    test "a plugin not dedicated to an event raises at compile time" do
      assert_raise RuntimeError, ~r/dedicated to an event/, fn ->
        Code.eval_string("""
        defmodule MishkaTmp.NoEventPlugin do
          use MishkaInstaller.Event.Hook
          @impl true
          def call(state), do: {:reply, state}
        end
        """)
      end
    end
  end

  describe "health/0 ===>" do
    test "reports health for every event in the system" do
      start_supervised!(CallBangPlugin)
      eventually(fn -> status(CallBangPlugin) == :started end)
      :ok = EventHandler.do_compile("callbang_evt", :start, false)

      reports = Hook.health()
      assert is_list(reports)
      assert Enum.any?(reports, &(&1.event == "callbang_evt"))
    end
  end

  describe "start retry + dependency-error callback ===>" do
    test "a plugin started before the system is ready retries via :start_again" do
      :persistent_term.put(:compile_status, "not_ready")
      on_exit(fn -> :persistent_term.put(:compile_status, "ready") end)

      start_supervised!(RetryPlugin)
      # not ready -> the plugin stays :starting (it has not registered/started yet)
      eventually(fn -> Keyword.get(RetryPlugin.get(), :status) == :starting end)

      # become ready and trigger the retry directly (instead of waiting the 1s timer)
      :persistent_term.put(:compile_status, "ready")
      send(RetryPlugin, :start_again)
      eventually(fn -> status(RetryPlugin) in [:started, :restarted, :registered] end)
    end

    test "on_dependency_error/1 fires when a plugin's registration hits a cycle" do
      :persistent_term.put({:hook_test, :dep_error}, nil)
      on_exit(fn -> :persistent_term.erase({:hook_test, :dep_error}) end)

      # CyclicA registers first (depends on CyclicB, not active yet) -> :held, no cycle.
      start_supervised!(CyclicA)
      eventually(fn -> Event.get(:name, CyclicA) != nil end)

      # CyclicB then closes the loop -> register rejects the cycle -> on_dependency_error runs.
      start_supervised!(CyclicB)
      eventually(fn -> :persistent_term.get({:hook_test, :dep_error}, nil) != nil end)

      assert {:error, [%{action: :register, field: :depends}]} =
               :persistent_term.get({:hook_test, :dep_error})
    end
  end

  defp status(mod) do
    case Event.get(:name, mod) do
      %{status: s} -> s
      _ -> nil
    end
  end

  defp eventually(fun, tries \\ 150)
  defp eventually(_fun, 0), do: flunk("condition was never met")

  defp eventually(fun, tries),
    do: if(fun.(), do: :ok, else: Process.sleep(20) && eventually(fun, tries - 1))
end
