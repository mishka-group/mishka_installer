defmodule MishkaInstallerTest.Support.ProcessHelpers do
  @moduledoc false
  # Stops a named server in a test's cleanup, and treats "it is already gone" as done.
  #
  # Most servers in these tests are started with `start_link` from the test process, so they die
  # with it, and an `on_exit` runs after that exit has been sent. A check that the server is alive
  # can pass and the server be gone by the time `GenServer.stop/1` reaches it, which exits the
  # caller with `:noproc` and fails a test that already passed. A server that stopped on its own is
  # the state the cleanup wanted.
  def stop_if_running(name) do
    GenServer.stop(name)
  catch
    :exit, {reason, _call} when reason in [:noproc, :normal, :shutdown, :killed] -> :ok
    :exit, {{:shutdown, _}, _call} -> :ok
  end
end
