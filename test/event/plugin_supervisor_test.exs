defmodule MishkaInstallerTest.Event.PluginSupervisorTest.First do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "group_evt", initial: %{priority: 1}
  @impl true
  def call(state), do: {:reply, Map.put(state, :first, true)}
end

defmodule MishkaInstallerTest.Event.PluginSupervisorTest.Second do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "group_evt", initial: %{priority: 2}
  @impl true
  def call(state), do: {:reply, Map.put(state, :second, true)}
end

defmodule MishkaInstallerTest.Event.PluginSupervisorTest.Other do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "other_group_evt"
  @impl true
  def call(state), do: {:reply, Map.put(state, :other, true)}
end

defmodule MishkaInstallerTest.Event.PluginSupervisorTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{Event, EventHandler, Hook, PluginSupervisor}
  alias MishkaInstallerTest.Event.PluginSupervisorTest.{First, Other, Second}
  alias MishkaInstallerTest.Support.ProcessHelpers

  @group MishkaInstallerTest.Event.PluginSupervisorTest.Plugins
  @other_group MishkaInstallerTest.Event.PluginSupervisorTest.OtherPlugins

  setup do
    :persistent_term.put(:compile_status, "ready")
    tmp = Path.join(System.tmp_dir!(), "mishka-group-#{System.unique_integer([:positive])}")

    Application.put_env(:mishka_installer, MishkaInstaller.MnesiaRepo,
      mnesia_dir: tmp,
      essential: [Event]
    )

    on_exit(fn ->
      ProcessHelpers.stop_if_running(MishkaInstaller.MnesiaRepo)
      ProcessHelpers.stop_if_running(EventHandler)
      File.rm_rf!(tmp)
    end)

    MishkaInstaller.subscribe("mnesia")
    MishkaInstaller.subscribe("event")
    start_supervised!(EventHandler)
    start_supervised!(MishkaInstaller.MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}
    assert_receive %{status: :event_status, channel: "mnesia", data: "ready"}
    :ok
  end

  # Each plugin broadcasts its record once it started; a synchronous compile after that builds the
  # chain from the stored records, so the chain holds every plugin waited for.
  defp await_started(plugins, event) do
    for plugin <- plugins, do: assert_receive(%{status: :start, data: %{name: ^plugin}})
    :ok = EventHandler.do_compile(event, :start, false)
  end

  defp children(supervisor),
    do: Map.new(Supervisor.which_children(supervisor), fn {id, pid, _, _} -> {id, pid} end)

  test "its plugins start, register and run in their event's chain" do
    start_supervised!({PluginSupervisor, name: @group, plugins: [First, Second]})
    await_started([First, Second], "group_evt")

    assert Hook.call("group_evt", %{}) == %{first: true, second: true}

    assert children(@group) == %{
             First => Process.whereis(First),
             Second => Process.whereis(Second)
           }

    assert Event.get(:name, First).status == :started
  end

  test "a killed plugin comes back with its status, and its event keeps running it" do
    start_supervised!({PluginSupervisor, name: @group, plugins: [First, Second]})
    await_started([First, Second], "group_evt")
    second = Process.whereis(Second)

    old = Process.whereis(First)
    ref = Process.monitor(old)
    Process.exit(old, :kill)
    assert_receive {:DOWN, ^ref, :process, ^old, :killed}

    assert_receive %{status: :register, data: %{name: First, status: :started}}
    new = Process.whereis(First)
    assert is_pid(new) and new != old
    assert Process.whereis(Second) == second
    assert Event.get(:name, First).status == :started
    assert Hook.call("group_evt", %{}) == %{first: true, second: true}
  end

  test "deaths past the group's limit stop only the group; its parent starts it again" do
    sibling = %{id: :sibling, start: {Agent, :start_link, [fn -> :sibling end]}}
    group = {PluginSupervisor, name: @group, plugins: [First], max_restarts: 0}

    parent =
      start_supervised!(%{
        id: :parent,
        type: :supervisor,
        start: {Supervisor, :start_link, [[sibling, group], [strategy: :one_for_one]]}
      })

    await_started([First], "group_evt")
    %{@group => group_pid, sibling: sibling_pid} = children(parent)

    group_ref = Process.monitor(group_pid)
    Process.exit(Process.whereis(First), :kill)
    assert_receive {:DOWN, ^group_ref, :process, ^group_pid, :shutdown}

    assert_receive %{status: :register, data: %{name: First, status: :started}}
    restarted = children(parent)
    assert restarted.sibling == sibling_pid
    assert is_pid(restarted[@group]) and restarted[@group] != group_pid
    assert Hook.call("group_evt", %{}) == %{first: true}
  end

  test "unregister/0 ends a plugin for good: its group does not start it again" do
    start_supervised!({PluginSupervisor, name: @group, plugins: [First, Second]})
    await_started([First, Second], "group_evt")

    pid = Process.whereis(First)
    ref = Process.monitor(pid)
    assert {:ok, _} = First.unregister()
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    assert children(@group)[First] == :undefined
    assert is_pid(children(@group)[Second])
    assert Event.get(:name, First) == nil
  end

  test "two groups under one parent do not clash" do
    start_supervised!({PluginSupervisor, name: @group, plugins: [First]})
    start_supervised!({PluginSupervisor, name: @other_group, plugins: [Other]})
    await_started([First], "group_evt")
    await_started([Other], "other_group_evt")

    assert Map.keys(children(@group)) == [First]
    assert Map.keys(children(@other_group)) == [Other]
    assert Hook.call("other_group_evt", %{}) == %{other: true}
  end

  test "child_spec/1 names the group by its name, or by the module without one" do
    assert %{id: @group, type: :supervisor} =
             PluginSupervisor.child_spec(name: @group, plugins: [First])

    assert %{id: PluginSupervisor, type: :supervisor} =
             PluginSupervisor.child_spec(plugins: [First])
  end
end
