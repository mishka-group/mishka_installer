defmodule MishkaInstaller.Helper.ExtraTest do
  use ExUnit.Case, async: true
  alias MishkaInstaller.Helper.Extra

  # Forwards every log event to the test that attached it. See `wait_for_logs/1`.
  defmodule LogProbe do
    def log(event, %{config: %{pid: pid}}), do: send(pid, {:log_probe, event})
  end

  doctest MishkaInstaller.Helper.Extra

  test "get_unix_time/0 returns the current unix time in seconds" do
    now = DateTime.utc_now() |> DateTime.to_unix()
    assert_in_delta Extra.get_unix_time(), now, 2
  end

  test "randstring/1 returns an uppercase alphanumeric string of the requested length" do
    str = Extra.randstring(16)
    assert String.length(str) == 16
    assert str == String.upcase(str)
    assert Regex.match?(~r/\A[0-9A-Z]+\z/, str)
    assert Extra.randstring(0) == ""
  end

  test "erlang_result/1 maps selectors to match-spec result bodies" do
    assert Extra.erlang_result(:all) == [:"$_"]
    assert Extra.erlang_result(:selected) == [:"$$"]
    assert Extra.erlang_result([:"$1"]) == [:"$1"]
  end

  describe "erlang_fields/4" do
    test "places numbered match vars for selected fields and wildcards elsewhere" do
      assert Extra.erlang_fields({Person}, [:id, :name, :age], [:name], 1) ==
               {Person, :_, :"$1", :_}
    end

    test "numbers multiple selected fields in order" do
      assert Extra.erlang_fields({Person}, [:id, :name, :age], [:id, :age], 1) ==
               {Person, :"$1", :_, :"$2"}
    end

    test "all wildcards when nothing is selected" do
      assert Extra.erlang_fields({Person}, [:id, :name], [], 1) == {Person, :_, :_}
    end
  end

  describe "isolate/1" do
    test "returns the result of the function" do
      assert Extra.isolate(fn -> {:done, 1} end) == {:ok, {:done, 1}}
      assert Extra.isolate(fn -> nil end) == {:ok, nil}
    end

    test "runs the function in another process" do
      caller = self()
      assert {:ok, pid} = Extra.isolate(fn -> self() end)
      assert pid != caller
    end

    test "does not hand the caller's process dictionary to the function" do
      Process.put(:isolate_probe, :caller_value)
      assert Extra.isolate(fn -> Process.get(:isolate_probe) end) == {:ok, nil}
    end

    @tag :capture_log
    test "an exception and a throw come back as {:exit, reason}, and are logged" do
      probe_logs()

      assert {:exit, {%RuntimeError{message: "boom"}, [_ | _]}} =
               Extra.isolate(fn -> raise "boom" end)

      assert {:exit, {{:nocatch, :thrown}, [_ | _]}} =
               Extra.isolate(fn -> throw(:thrown) end)

      wait_for_logs(["boom", "thrown"])
    end

    test "an exit and a kill come back as {:exit, reason}" do
      assert Extra.isolate(fn -> exit(:gone) end) == {:exit, :gone}
      assert Extra.isolate(fn -> exit(:kill) end) == {:exit, :kill}
      assert Extra.isolate(fn -> Process.exit(self(), :kill) end) == {:exit, :killed}
    end

    test "stops the function when the caller is killed while it runs" do
      test_pid = self()

      caller =
        spawn(fn ->
          Extra.isolate(fn ->
            send(test_pid, {:running, self()})
            Process.sleep(:infinity)
          end)
        end)

      assert_receive {:running, worker}
      worker_ref = Process.monitor(worker)
      Process.exit(caller, :kill)

      assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}
    end

    test "leaves nothing in the caller's mailbox" do
      {:ok, _} = Extra.isolate(fn -> :ok end)
      {:exit, :gone} = Extra.isolate(fn -> exit(:gone) end)
      refute_received _message
    end
  end

  # THE CRASH IS REPORTED BY THE CRASHED PROCESS, NOT BY THIS ONE, and the emulator hands the report
  # to the logger on its own time. A capture that ends when `isolate/1` returns can end before the
  # report arrives, which is how this test failed on both CI runners while passing every local run.
  # So the test waits for the reports themselves: a handler sends each log event here, and
  # `wait_for_logs/1` returns once every expected text has been seen, whatever order they come in.
  defp probe_logs do
    id = :"isolate_log_probe_#{System.unique_integer([:positive])}"
    :ok = :logger.add_handler(id, LogProbe, %{config: %{pid: self()}})
    on_exit(fn -> :logger.remove_handler(id) end)
  end

  defp wait_for_logs([]), do: :ok

  defp wait_for_logs(texts) do
    receive do
      {:log_probe, event} ->
        logged = event |> :logger_formatter.format(%{template: [:msg]}) |> IO.chardata_to_string()
        wait_for_logs(Enum.reject(texts, &String.contains?(logged, &1)))
    after
      5_000 -> flunk("not logged within 5 seconds: #{inspect(texts)}")
    end
  end
end
