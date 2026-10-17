defmodule MishkaInstaller.Helper.Extra do
  @moduledoc """
  Small, dependency-free helpers used across `MishkaInstaller`.

  It covers unix timestamps, random strings, running a function in an isolated process, and two
  helpers that build Erlang [match specifications](https://www.erlang.org/doc/apps/erts/match_spec)
  used by the Mnesia query layer (`MishkaInstaller.Helper.MnesiaAssistant`).
  """

  @alphabet Enum.concat([?0..?9, ?A..?Z, ?a..?z])

  @doc """
  Returns the current time as a unix timestamp in seconds.

  ## Examples

  ```elixir
  iex> is_integer(MishkaInstaller.Helper.Extra.get_unix_time())
  true
  ```
  """
  @spec get_unix_time() :: integer()
  def get_unix_time(), do: DateTime.utc_now() |> DateTime.to_unix()

  @doc """
  Returns an uppercase random string of `count` characters.

  > Not suitable for security-sensitive values.

  ## Examples

  ```elixir
  iex> String.length(MishkaInstaller.Helper.Extra.randstring(8))
  8
  ```
  """
  @spec randstring(non_neg_integer()) :: String.t()
  def randstring(count) do
    Stream.repeatedly(fn -> Enum.random(@alphabet) end)
    |> Enum.take(count)
    |> List.to_string()
    |> String.upcase()
  end

  @doc """
  Runs `fun` in its own process and waits for it.

  Returns `{:ok, result}` when `fun` returns, and `{:exit, reason}` when the process dies first
  (an exception, a throw, an exit or a kill): `reason` is the exit reason of the process, so a
  raised exception arrives as `{exception, stacktrace}`. Nothing `fun` does reaches the caller as
  an exception, and `fun` runs without the caller's process dictionary.

  The process lives and dies with the caller: when the caller is killed or stopped while `fun` is
  running, `fun` is stopped too.

  ## Examples

  ```elixir
  iex> MishkaInstaller.Helper.Extra.isolate(fn -> 1 + 1 end)
  {:ok, 2}
  ```
  """
  @spec isolate((-> result)) :: {:ok, result} | {:exit, term()} when result: term()
  def isolate(fun) when is_function(fun, 0) do
    caller = self()
    ref = make_ref()
    {guard, guard_ref} = spawn_monitor(fn -> guard(caller, ref, fun) end)

    receive do
      {^ref, outcome} ->
        Process.demonitor(guard_ref, [:flush])
        outcome

      {:DOWN, ^guard_ref, :process, ^guard, reason} ->
        {:exit, reason}
    end
  end

  # Runs `fun` in a process linked to this one and sends the caller how it ended; stops `fun` as soon
  # as the caller is gone.
  defp guard(caller, ref, fun) do
    Process.flag(:trap_exit, true)
    caller_ref = Process.monitor(caller)
    guard = self()
    worker = spawn_link(fn -> send(guard, {:worker_done, self(), fun.()}) end)

    receive do
      {:worker_done, ^worker, result} -> send(caller, {ref, {:ok, result}})
      {:EXIT, ^worker, reason} -> send(caller, {ref, {:exit, reason}})
      {:DOWN, ^caller_ref, :process, ^caller, _reason} -> Process.exit(worker, :kill)
    end

    :ok
  end

  @doc """
  Translates a result selector into the Erlang match-spec result body.

  - `:all` -> `[:"$_"]` (whole record)
  - `:selected` -> `[:"$$"]` (selected fields)
  - any other term is returned unchanged.
  """
  @spec erlang_result(:all | :selected | term()) :: term()
  def erlang_result(:all), do: [:"$_"]
  def erlang_result(:selected), do: [:"$$"]
  def erlang_result(term), do: term

  @doc """
  Builds the head tuple of an Erlang match specification.

  Walks the record `keys` and, for each field present in `fields`, places a numbered match
  variable (`:"$1"`, `:"$2"`, ...); every other field becomes the wildcard `:_`.

  ## Examples

  ```elixir
  iex> MishkaInstaller.Helper.Extra.erlang_fields({Person}, [:id, :name], [:name], 1)
  {Person, :_, :"$1"}
  ```
  """
  @spec erlang_fields(tuple(), [atom()], [atom()], pos_integer()) :: tuple()
  def erlang_fields(tuple, [], _keys, _num), do: tuple

  def erlang_fields(tuple, [field | rest], keys, num) do
    selected? = field in keys

    tuple
    |> Tuple.insert_at(tuple_size(tuple), if(selected?, do: :"$#{num}", else: :_))
    |> erlang_fields(rest, keys, if(selected?, do: num + 1, else: num))
  end
end
