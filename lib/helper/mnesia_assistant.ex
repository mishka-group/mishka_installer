defmodule MishkaInstaller.Helper.MnesiaAssistant do
  @moduledoc """
  A focused Elixir wrapper around the Erlang [`:mnesia`](https://www.erlang.org/doc/man/mnesia)
  runtime database used by `MishkaInstaller`.

  It exposes only what the installer needs and standardises a few outputs. The full API is split
  into:

  - `MishkaInstaller.Helper.MnesiaAssistant.Schema` — schema creation
  - `MishkaInstaller.Helper.MnesiaAssistant.Table` — table create / wait / clear / keys
  - `MishkaInstaller.Helper.MnesiaAssistant.Query` — read / write / delete / select
  - `MishkaInstaller.Helper.MnesiaAssistant.Transaction` — transaction / ets / error mapping
  - `MishkaInstaller.Helper.MnesiaAssistant.Information` — `system_info`
  - `MishkaInstaller.Helper.MnesiaAssistant.Error` — error description + logging
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
  Connects this (running, empty-schema) node to the cluster `nodes`. Delegates to
  `:mnesia.change_config/2`. Returns `{:ok, connected_nodes}` or `{:error, reason}`.
  """
  @spec change_config([node()]) :: {:ok, [node()]} | {:error, term()}
  def change_config(nodes), do: :mnesia.change_config(:extra_db_nodes, nodes)

  @doc """
  Subscribes the calling process to Mnesia `what` events (e.g. `:system`).
  Delegates to `:mnesia.subscribe/1`.
  """
  @spec subscribe(term()) :: {:ok, node()} | {:error, term()}
  def subscribe(what), do: :mnesia.subscribe(what)

  @doc "Unsubscribes from Mnesia `what` events. Delegates to `:mnesia.unsubscribe/1`."
  @spec unsubscribe(term()) :: {:ok, node()} | {:error, term()}
  def unsubscribe(what), do: :mnesia.unsubscribe(what)

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
  iex> MishkaInstaller.Helper.MnesiaAssistant.tuple_to_map([{Person, 1, "a"}], [:id, :name], nil, [])
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
