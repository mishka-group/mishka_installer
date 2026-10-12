# Plugins on events whose state is a tuple, as a LiveView callback's answer is: each marks the map it
# carries, so the chain's result shows whether it was kept.
defmodule MishkaInstallerTest.Event.StateShapeTest.NoReply do
  @moduledoc false
  def call({:noreply, socket}), do: {:reply, {:noreply, Map.put(socket, :seen, true)}}
end

defmodule MishkaInstallerTest.Event.StateShapeTest.MountReturn do
  @moduledoc false
  def call({:ok, socket, opts}), do: {:reply, {:ok, Map.put(socket, :seen, true), opts}}
end

defmodule MishkaInstallerTest.Event.StateShapeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias MishkaInstaller.Event.{Event, ModuleStateCompiler}
  alias MishkaInstallerTest.Event.StateShapeTest.{MountReturn, NoReply}

  @events ["shape_noreply_evt", "shape_mount_evt", "shape_empty_evt", "shape_binary_evt"]

  setup do
    on_exit(fn -> ModuleStateCompiler.purge(@events) end)
    :ok
  end

  defp compiled(event, plugins) do
    built =
      for name <- plugins do
        {:ok, plugin} = Event.builder(%{name: name, event: event, extension: :mishka_installer})
        plugin
      end

    :ok = ModuleStateCompiler.create(built, event)
    ModuleStateCompiler.module_event_name(event)
  end

  # Runs `fun` and returns its answer, failing the test when the chain logged a raise.
  defp quietly(fun) do
    {answer, log} = with_log(fun)
    refute log =~ "plugin pipeline raised"
    answer
  end

  test "a 2-tuple state keeps what its plugins returned" do
    module = compiled("shape_noreply_evt", [NoReply])

    assert quietly(fn -> module.call({:noreply, %{}}) end) == {:noreply, %{seen: true}}
  end

  test "a 3-tuple state keeps what its plugins returned" do
    module = compiled("shape_mount_evt", [MountReturn])

    assert quietly(fn -> module.call({:ok, %{}, layout: :app}) end) ==
             {:ok, %{seen: true}, layout: :app}
  end

  test "an event with no plugins hands any state back as it came" do
    module = compiled("shape_empty_evt", [])

    for state <- [{:noreply, %{}}, {:ok, %{}, layout: :app}, "body { color: red }", :done, 42] do
      assert quietly(fn -> module.call(state) end) == state
    end
  end

  test "a list or map state still takes the private data merged into it" do
    module = compiled("shape_binary_evt", [])

    assert module.call(%{a: 1}, private: %{b: 2}) == %{a: 1, b: 2}
    assert module.call([a: 1], private: [b: 2]) == [a: 1, b: 2]
    assert module.call("css", private: %{b: 2}) == "css"
  end
end
