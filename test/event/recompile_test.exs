# `Blocker` holds a caller inside the chain until the test releases it, so the event can be rebuilt
# while that caller still runs the version it entered. `Two` and `Three` mark which version ran.
defmodule MishkaInstallerTest.Event.RecompileTest.Blocker do
  @moduledoc false
  def call(%{block: test} = state) do
    send(test, {:inside, self()})

    receive do
      :release -> {:reply, Map.put(state, :blocked, true)}
    end
  end

  def call(state), do: {:reply, state}
end

defmodule MishkaInstallerTest.Event.RecompileTest.Two do
  @moduledoc false
  def call(state), do: {:reply, Map.put(state, :two, true)}
end

defmodule MishkaInstallerTest.Event.RecompileTest.Three do
  @moduledoc false
  def call(state), do: {:reply, Map.put(state, :three, true)}
end

defmodule MishkaInstallerTest.Event.RecompileTest do
  use ExUnit.Case, async: false

  alias MishkaInstaller.Event.{Event, Hook, ModuleStateCompiler}
  alias MishkaInstallerTest.Event.RecompileTest.{Blocker, Three, Two}

  @event "recompile_running_evt"

  setup do
    on_exit(fn -> ModuleStateCompiler.purge(@event) end)
    compile([Blocker])
  end

  defp compile(plugins) do
    built =
      for name <- plugins do
        {:ok, plugin} = Event.builder(%{name: name, event: @event, extension: :mishka_installer})
        plugin
      end

    :ok = ModuleStateCompiler.purge_create(built, @event)
  end

  # A caller that runs the event and stops inside `Blocker` until it gets `:release`.
  defp blocked_caller do
    test = self()

    {caller, ref} =
      spawn_monitor(fn -> send(test, {:answer, Hook.call(@event, %{block: test})}) end)

    assert_receive {:inside, ^caller}
    {caller, ref}
  end

  defp finishes(caller, ref) do
    test = self()
    send(caller, :release)
    assert_receive {:answer, %{block: ^test, blocked: true}}
    assert_receive {:DOWN, ^ref, :process, ^caller, :normal}
  end

  test "a caller inside a plugin finishes normally while its event is rebuilt twice" do
    {caller, ref} = blocked_caller()

    compile([Blocker, Two])
    compile([Blocker, Three])
    assert Hook.call(@event, %{}) == %{three: true}

    finishes(caller, ref)
  end

  test "a caller inside a plugin finishes normally while its event is rebuilt many times" do
    {caller, ref} = blocked_caller()

    for plugins <- [[Blocker, Two], [Blocker, Three], [Two], [Three], [Blocker, Two, Three]] do
      compile(plugins)
    end

    assert Hook.call(@event, %{}) == %{two: true, three: true}
    finishes(caller, ref)
  end

  test "a caller inside a plugin finishes normally when its rebuilt event is purged" do
    {caller, ref} = blocked_caller()

    compile([Blocker, Two])
    :ok = ModuleStateCompiler.purge(@event)
    assert ModuleStateCompiler.event_module(@event) == nil
    assert Hook.call(@event, %{}) == %{}

    finishes(caller, ref)
  end

  test "once no caller runs an old version, the event is built under its own name again" do
    {caller, ref} = blocked_caller()
    compile([Blocker, Two])
    compile([Blocker, Three])
    finishes(caller, ref)

    compile([Two])
    compile([Three])

    assert ModuleStateCompiler.event_module(@event) ==
             ModuleStateCompiler.module_event_name(@event)

    assert Hook.call(@event, %{}) == %{three: true}
  end
end
