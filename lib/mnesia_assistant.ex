defmodule MishkaInstaller.MnesiaAssistant do
  @moduledoc """
  A focused Elixir wrapper around the Erlang [`:mnesia`](https://www.erlang.org/doc/man/mnesia)
  runtime database used by `MishkaInstaller`.

  It exposes only what the installer needs and standardises a few outputs. The full API is split
  into:

  - `MishkaInstaller.MnesiaAssistant.Schema` — schema creation
  - `MishkaInstaller.MnesiaAssistant.Table` — table create / wait / clear / keys
  - `MishkaInstaller.MnesiaAssistant.Query` — read / write / delete / select
  - `MishkaInstaller.MnesiaAssistant.Transaction` — transaction / ets / error mapping
  - `MishkaInstaller.MnesiaAssistant.Information` — `system_info`
  - `MishkaInstaller.MnesiaAssistant.Error` — error description + logging
  """
  alias MishkaInstaller.Helper.Extra

  @doc """
  Starts the Mnesia application. Delegates to `:mnesia.start/0`.
  """
  @spec start() :: :ok | {:error, term()}
  def start(), do: :mnesia.start()

  @doc """
  Stops the Mnesia application. Delegates to `:mnesia.stop/0`.
  """
  @spec stop() :: :stopped | {:error, term()}
  def stop(), do: :mnesia.stop()

  @doc """
  Translates a result selector into the Erlang match-spec result body. See
  `MishkaInstaller.Helper.Extra.erlang_result/1`.
  """
  defdelegate er(operation), to: Extra, as: :erlang_result

  @doc """
  Builds the head tuple of an Erlang match specification. See
  `MishkaInstaller.Helper.Extra.erlang_fields/4`.
  """
  defdelegate erl_fields(tuple, fields, keys, num), to: Extra, as: :erlang_fields

  @doc """
  Converts Mnesia record tuples into maps or structs.

  - `:"$end_of_table"` becomes `[]`.
  - `{records, cont}` (a paginated select result) keeps the continuation: `{converted, cont}`.
  - a list of record tuples becomes a list; each tuple is zipped with `fields` (the leading record
    tag is dropped), `drop` keys are removed, and — when `struct` is not `nil` — wrapped with
    `struct!/2`.

  ## Examples

  ```elixir
  iex> MishkaInstaller.MnesiaAssistant.tuple_to_map([{Person, 1, "a"}], [:id, :name], nil, [])
  [%{id: 1, name: "a"}]
  ```
  """
  @spec tuple_to_map(list() | tuple() | :"$end_of_table", [atom()], module() | nil, [atom()]) ::
          list() | {list(), any()}
  def tuple_to_map(:"$end_of_table", _fields, _struct, _drop), do: []

  def tuple_to_map({records, cont}, fields, struct, drop) do
    {tuple_to_map(records, fields, struct, drop), cont}
  end

  def tuple_to_map(records, fields, struct, drop) when is_list(records) do
    Enum.map(records, fn item ->
      map =
        fields
        |> Enum.zip(item |> Tuple.delete_at(0) |> Tuple.to_list())
        |> Map.new()
        |> Map.drop(drop)

      if is_nil(struct), do: map, else: struct!(struct, map)
    end)
  end
end
