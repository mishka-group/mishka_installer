defmodule MishkaInstaller.Helper.ExtraTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog, only: [capture_log: 1]
  alias MishkaInstaller.Helper.Extra

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

    test "an exception and a throw come back as {:exit, reason}, and are logged" do
      log =
        capture_log(fn ->
          assert {:exit, {%RuntimeError{message: "boom"}, [_ | _]}} =
                   Extra.isolate(fn -> raise "boom" end)

          assert {:exit, {{:nocatch, :thrown}, [_ | _]}} =
                   Extra.isolate(fn -> throw(:thrown) end)

          flush_logs()
        end)

      assert log =~ "boom"
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

  # The emulator reports a crashed process through `:logger_proxy`; once it has answered, the report
  # reached the handlers.
  defp flush_logs do
    :sys.get_state(:logger_proxy)
    Logger.flush()
  end
end
