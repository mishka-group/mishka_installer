defmodule MishkaInstallerTest.Support.Eventually do
  @moduledoc false
  # Asks again until a check passes or the time is up, and returns the last answer.
  #
  # With `queue: true` an event's module is recompiled after the call returns, and the broadcasts a
  # test waits for do not say which compile they come from: a start, a dependent's recompile and a
  # stop can each send `:purge_create`. A test that counted messages and then read the module once
  # sometimes read it before the compile it was waiting for. So the test asks for the state it wants
  # instead, as often as it takes within the suite's `assert_receive` timeout (`test_helper.exs`).
  #
  # The module is purged and created again during a compile, so a call into it can fail for a
  # moment; that counts as "not yet".
  @interval 20

  def eventually(check, timeout \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    ask(check, deadline)
  end

  defp ask(check, deadline) do
    answer =
      try do
        check.()
      rescue
        _error -> false
      end

    if answer || System.monotonic_time(:millisecond) >= deadline do
      answer
    else
      Process.sleep(@interval)
      ask(check, deadline)
    end
  end
end
