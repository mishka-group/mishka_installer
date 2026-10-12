# A plugin that marks the map it is handed, and one that also keeps the `meta` it was given, so a
# result shows whether the chain ran and what reached the plugins.
defmodule MishkaInstallerTest.Event.CannotRunTest.Mark do
  @moduledoc false
  def call(state), do: {:reply, Map.put(state, :marked, true)}
end

defmodule MishkaInstallerTest.Event.CannotRunTest.KeepMeta do
  @moduledoc false
  def call(state, meta), do: {:reply, Map.put(state, :meta, meta)}
end

defmodule MishkaInstallerTest.Event.CannotRunTest do
  use ExUnit.Case, async: false

  alias MishkaInstaller.Event.{Event, Hook, ModuleStateCompiler}
  alias MishkaInstallerTest.Event.CannotRunTest.{KeepMeta, Mark}

  @not_loaded MishkaInstallerTest.Event.CannotRunTest.NotLoaded
  @stub "cannot_run_stub_evt"
  @runs "cannot_run_runs_evt"
  @events [@stub, @runs, "cannot_run_never_compiled_evt"]

  setup do
    on_exit(fn -> ModuleStateCompiler.purge(@events) end)
    :ok
  end

  defp compile(event, plugins, inaccessible \\ []) do
    built =
      for name <- plugins do
        {:ok, plugin} = Event.builder(%{name: name, event: event, extension: :mishka_installer})
        plugin
      end

    :ok = ModuleStateCompiler.create(built, event, inaccessible)
  end

  describe "an event that cannot run" do
    setup do
      compile(@stub, [Mark, @not_loaded], [@not_loaded])
    end

    test "hands back the state it was given, whatever its shape" do
      for state <- [%{a: 1}, [a: 1], {:noreply, %{a: 1}}, "body {}", nil] do
        assert Hook.call(@stub, state) == state
        assert Hook.call!(@stub, state) == state
      end
    end

    test "answers the cannot_run option instead" do
      assert Hook.call(@stub, %{a: 1}, cannot_run: :refused) == :refused
      assert Hook.call!(@stub, %{a: 1}, cannot_run: :refused) == :refused

      assert Hook.call(@stub, %{allowed?: true}, cannot_run: %{allowed?: false}) ==
               %{allowed?: false}
    end

    test "answers the cannot_run option as given, beside private, return and meta" do
      args = [private: %{p: 1}, return: true, meta: %{m: 1}, cannot_run: {:error, :cannot_run}]

      assert Hook.call(@stub, %{a: 1}, args) == {:error, :cannot_run}
      assert Hook.call!(@stub, %{a: 1}, args) == {:error, :cannot_run}
    end
  end

  describe "an event whose plugins all run" do
    setup do
      compile(@runs, [Mark, KeepMeta])
    end

    test "ignores the cannot_run option" do
      assert Hook.call(@runs, %{a: 1}, cannot_run: :refused) == %{a: 1, marked: true, meta: nil}
      assert Hook.call!(@runs, %{a: 1}, cannot_run: :refused) == %{a: 1, marked: true, meta: nil}
    end

    test "merges private and hands meta to its plugins without the cannot_run option" do
      args = [private: %{p: 1}, meta: %{m: 1}, cannot_run: :refused]

      assert Hook.call(@runs, %{a: 1}, args) == %{a: 1, marked: true, meta: %{m: 1}, p: 1}
      assert Hook.call!(@runs, %{a: 1}, args) == %{a: 1, marked: true, meta: %{m: 1}, p: 1}
    end
  end

  test "an event that is not compiled hands back the state, with or without the option" do
    assert Hook.call("cannot_run_never_compiled_evt", %{a: 1}) == %{a: 1}
    assert Hook.call("cannot_run_never_compiled_evt", %{a: 1}, cannot_run: :refused) == %{a: 1}
  end
end
