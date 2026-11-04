defmodule MishkaInstallerTest.Event.CallArgsTest.Mark do
  @moduledoc false
  def call(state) when is_map(state), do: {:reply, Map.put(state, :marked, true)}
  def call(state) when is_list(state), do: {:reply, Keyword.put(state, :marked, true)}
  def call(state), do: {:reply, state}
end

defmodule MishkaInstallerTest.Event.CallArgsTest.Raiser do
  @moduledoc false
  def call(_state), do: raise(ArgumentError, "plugin boom")
end

defmodule MishkaInstallerTest.Event.CallArgsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias MishkaInstaller.Event.{Event, Hook, ModuleStateCompiler}
  alias MishkaInstallerTest.Event.CallArgsTest.{Mark, Raiser}

  @runs "call_args_runs_evt"
  @raises "call_args_raises_evt"

  setup do
    compile(@runs, [Mark])
    compile(@raises, [Raiser])
    on_exit(fn -> ModuleStateCompiler.purge([@runs, @raises]) end)
    :ok
  end

  defp compile(event, plugins) do
    built =
      for name <- plugins do
        {:ok, plugin} = Event.builder(%{name: name, event: event, extension: :mishka_installer})
        plugin
      end

    :ok = ModuleStateCompiler.create(built, event)
  end

  describe "args that are not a list" do
    test "are refused with an ArgumentError before any plugin runs" do
      for args <- [nil, %{}, "str", :raised, {:raised, :x}],
          event <- [@runs, @raises, "call_args_never_compiled_evt"],
          call <- [&Hook.call/3, &Hook.call!/3] do
        error = assert_raise ArgumentError, fn -> call.(event, %{a: 1}, args) end
        assert error.message =~ "keyword list"
        assert error.message =~ inspect(args)
      end
    end

    test "never reach the rescue of a plugin that raises" do
      log =
        capture_log(fn ->
          assert_raise ArgumentError, fn -> Hook.call(@raises, %{a: 1}, nil) end
        end)

      refute log =~ "raised"
    end

    test "are refused by the compiled module too" do
      module = ModuleStateCompiler.event_module(@raises)
      assert_raise FunctionClauseError, fn -> module.call(%{a: 1}, nil) end
    end
  end
end
