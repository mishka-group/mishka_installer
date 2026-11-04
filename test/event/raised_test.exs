# Plugins that mark the map, raise, break the reply contract, and tell the caller they ran: the
# chain runs in the caller's process, so `Tail` sends to the test process itself.
defmodule MishkaInstallerTest.Event.RaisedTest.Mark do
  @moduledoc false
  def call(state), do: {:reply, Map.put(state, :marked, true)}
end

defmodule MishkaInstallerTest.Event.RaisedTest.Raiser do
  @moduledoc false
  def call(_state), do: raise(ArgumentError, "plugin boom")
end

defmodule MishkaInstallerTest.Event.RaisedTest.BadReply do
  @moduledoc false
  def call(state), do: {:ok, state}
end

defmodule MishkaInstallerTest.Event.RaisedTest.Tail do
  @moduledoc false
  def call(state) do
    send(self(), :tail_ran)
    {:reply, state}
  end
end

defmodule MishkaInstallerTest.Event.RaisedTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias MishkaInstaller.Event.{Event, Hook, ModuleStateCompiler}
  alias MishkaInstallerTest.Event.RaisedTest.{BadReply, Mark, Raiser, Tail}

  @raises "raised_raises_evt"
  @bad_reply "raised_bad_reply_evt"
  @runs "raised_runs_evt"
  @stub "raised_stub_evt"
  @events [@raises, @bad_reply, @runs, @stub]

  setup do
    compile(@raises, [Mark, Raiser, Tail])
    compile(@bad_reply, [Mark, BadReply, Tail])
    compile(@runs, [Mark, Tail])
    compile(@stub, [Mark, Raiser], [Raiser])
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

  describe "a plugin that raises" do
    @describetag :capture_log

    test "answers the raised option, and the plugins after it do not run" do
      assert Hook.call(@raises, %{a: 1}, raised: :failed) == :failed
      refute_received :tail_ran

      assert Hook.call!(@raises, %{a: 1}, raised: {:error, :raised}) == {:error, :raised}
      refute_received :tail_ran
    end

    test "answers the state it was given without the option" do
      assert Hook.call(@raises, %{a: 1}) == %{a: 1}
      assert Hook.call!(@raises, %{a: 1}, meta: %{m: 1}) == %{a: 1}
      refute_received :tail_ran
    end

    test "answers the raised option before return and private" do
      args = [return: true, private: %{p: 1}, meta: %{m: 1}, raised: :failed]

      assert Hook.call(@raises, %{a: 1}, args) == :failed
      assert Hook.call!(@raises, %{a: 1}, args) == :failed
    end
  end

  describe "a plugin whose reply is not {:reply, _}" do
    @describetag :capture_log

    test "answers the raised option, or the state it was given" do
      assert Hook.call(@bad_reply, %{a: 1}, raised: :failed) == :failed
      assert Hook.call(@bad_reply, %{a: 1}) == %{a: 1}
      refute_received :tail_ran
    end
  end

  test "an event whose plugins all run ignores the raised option" do
    assert Hook.call(@runs, %{a: 1}, raised: :failed) == %{a: 1, marked: true}
    assert_received :tail_ran

    assert Hook.call(@runs, %{a: 1}, raised: :failed, return: true) == %{a: 1}

    merged = Hook.call!(@runs, %{a: 1}, raised: :failed, private: %{p: 1})
    assert merged == %{a: 1, marked: true, p: 1}
  end

  test "an event that cannot run answers cannot_run, not raised" do
    assert Hook.call(@stub, %{a: 1}, cannot_run: :refused, raised: :failed) == :refused
    assert Hook.call(@stub, %{a: 1}, raised: :failed) == %{a: 1}
  end

  test "the log names the event and the plugin frame that raised" do
    log = capture_log(fn -> Hook.call(@raises, %{a: 1}, raised: :failed) end)

    assert log =~ inspect(@raises)
    assert log =~ "plugin boom"
    assert log =~ "#{inspect(Raiser)}.call/1"
  end
end
