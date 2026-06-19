defmodule MishkaInstaller.Helper.Extra do
  @moduledoc """
  Small, dependency-free helpers used across `MishkaInstaller`.

  It covers unix timestamps, random strings, and two helpers that build Erlang
  [match specifications](https://www.erlang.org/doc/apps/erts/match_spec) used by the
  Mnesia query layer (`MishkaInstaller.MnesiaAssistant`).
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
