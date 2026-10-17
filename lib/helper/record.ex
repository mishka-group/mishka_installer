defmodule MishkaInstaller.Helper.Record do
  @moduledoc """
  The Mnesia record functions that `MishkaInstaller.Event.Event` and
  `MishkaInstaller.Installer.Installer` share.

  Every function takes the record's module first: a `GuardedStruct` module that exports `keys/0`
  and whose table is created from its `database_config/0`. Reads return the stored rows as structs
  of that module; writes return `{:ok, struct}` or the standard
  `{:error, [%{message: _, field: _, action: _}]}`.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  """
  alias MishkaInstaller.Helper.{Extra, MnesiaAssistant}
  alias MishkaInstaller.Helper.MnesiaAssistant.{Query, Table, Transaction}
  alias MishkaInstaller.Helper.MnesiaAssistant.Error, as: MError

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  ####################################################################################
  ########################## (▰˘◡˘▰) Query (▰˘◡˘▰) ############################
  ####################################################################################
  @doc """
  Returns every stored row of `module` as a struct of `module`, or `[]` when the read aborts.

  ## Example:

  ```elixir
  all(MishkaInstaller.Installer.Installer)
  ```
  """
  @spec all(module()) :: [struct()]
  def all(module) do
    keys = module.keys()
    pattern = ([module] ++ Enum.map(keys, fn _key -> :_ end)) |> List.to_tuple()

    Transaction.transaction(fn -> Query.match_object(pattern) end)
    |> case do
      {:atomic, res} ->
        MnesiaAssistant.tuple_to_map(res, keys, module, [])

      {:aborted, reason} ->
        Transaction.transaction_error(reason, module, "reading", :global, :database)
        []
    end
  end

  @doc """
  Returns the row of `module` whose id is `id` as a struct of `module`, or `nil` when there is none
  or the read aborts.

  ## Example:

  ```elixir
  get(MishkaInstaller.Installer.Installer, "c63aea42-209a-40fb-b5c6-a0d28ee7e25b")
  ```
  """
  @spec get(module(), String.t()) :: struct() | nil
  def get(module, id) do
    Transaction.transaction(fn -> Query.read(module, id) end)
    |> case do
      {:atomic, res} ->
        res |> MnesiaAssistant.tuple_to_map(module.keys(), module, []) |> List.first()

      {:aborted, reason} ->
        Transaction.transaction_error(reason, module, "reading", :global, :database)
        nil
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Write (▰˘◡˘▰) #############################
  ####################################################################################
  @doc """
  Writes `struct` (a struct of `module`, as `module.builder/1` returns it) in a durable transaction
  and returns `{:ok, struct}`, or the error of the aborted transaction.

  ## Example:

  ```elixir
  {:ok, struct} = Installer.builder(%{app: "demo", version: "0.1.0", path: "demo"})
  store(MishkaInstaller.Installer.Installer, struct)
  ```
  """
  @spec store(module(), struct()) :: {:ok, struct()} | error_return()
  def store(module, struct) do
    Transaction.durable_transaction(fn -> Query.write(to_tuple(module, struct)) end)
    |> case do
      {:atomic, _res} ->
        {:ok, struct}

      {:aborted, reason} ->
        Transaction.transaction_error(reason, module, "storing", :global, :database)
    end
  end

  @doc """
  Removes every row of `module`'s table.

  Returns `{:ok, :atomic}`, or `{:error, reason, description}` when Mnesia refuses.

  ## Example:

  ```elixir
  drop(MishkaInstaller.Installer.Installer)
  ```
  """
  @spec drop(module()) :: {:ok, :atomic} | {:error, any(), charlist()}
  def drop(module) do
    Table.clear_table(module)
    |> MError.error_description(module)
  end

  @doc """
  Answers `:ok` when `selected` (the struct a read returned, or `nil`) is `nil`, meaning the record
  does not exist yet, and the error with the action `:unique` otherwise. `noun` names the record in
  the message.

  ## Example:

  ```elixir
  unique(Installer.get(:app, "demo"), "library")
  ```
  """
  @spec unique(struct() | nil, String.t()) :: :ok | error_return()
  def unique(nil, _noun), do: :ok

  def unique(_selected, noun) do
    message = "This #{noun} already exists in the database."
    {:error, [%{message: message, field: :global, action: :unique}]}
  end

  @doc """
  Deletes the row of `module` that `selected` (the struct a read returned, or `nil`) came from, in a
  durable transaction, and returns `{:ok, selected}`.

  A `nil` selection is the error of a record that is incorrect or already deleted, with the action
  `:delete`.

  ## Example:

  ```elixir
  delete(MishkaInstaller.Installer.Installer, Installer.get(:app, "demo"))
  ```
  """
  @spec delete(module(), struct() | nil) :: {:ok, struct()} | error_return()
  def delete(_module, nil) do
    message = "The ID of the record you want to delete is incorrect or has already been deleted."
    {:error, [%{message: message, field: :global, action: :delete}]}
  end

  def delete(module, data) do
    Transaction.durable_transaction(fn -> Query.delete(module, Map.get(data, :id), :write) end)
    |> case do
      {:atomic, _res} ->
        {:ok, data}

      {:aborted, reason} ->
        Transaction.transaction_error(reason, module, "deleting", :global, :database)
    end
  end

  @doc """
  Merges `updated_to` onto the stored row of `module` found by `field` (`:id`, or an indexed field
  such as `:name` or `:app`) and `value`, and returns `{:ok, struct}`.

  The row is read again inside the durable transaction under a write lock, so two concurrent
  updates of the same row cannot start from the same old values and lose one another's fields. The
  `:id` of `updated_to` is ignored and `:updated_at` is set to the time of the write.

  `build` receives `{:root, merged_map, :edit}` and returns `{:ok, struct}` or `{:error, errors}`;
  the error is returned as it is and nothing is written. When no row matches, the error has the
  action `:write`.

  ## Example:

  ```elixir
  update(MishkaInstaller.Event.Event, :name, MyPlugin, %{status: :stopped}, &Event.builder/1)
  ```
  """
  @spec update(module(), atom(), term(), map(), (tuple() -> {:ok, struct()} | error_return())) ::
          {:ok, struct()} | error_return()
  def update(module, field, value, updated_to, build) when is_function(build, 1) do
    Transaction.durable_transaction(fn ->
      case locked_read(module, field, value) do
        nil ->
          :mnesia.abort(:record_not_found)

        data ->
          merged =
            data
            |> Map.merge(Map.drop(updated_to, [:id]))
            |> Map.merge(%{updated_at: Extra.get_unix_time()})

          case build.({:root, merged, :edit}) do
            {:ok, struct} ->
              module |> to_tuple(struct) |> Query.write()
              struct

            {:error, _} = error ->
              :mnesia.abort(error)
          end
      end
    end)
    |> case do
      {:atomic, struct} ->
        {:ok, struct}

      {:aborted, :record_not_found} ->
        message =
          "The ID of the record you want to update is incorrect or has already been deleted."

        {:error, [%{message: message, field: :global, action: :write}]}

      {:aborted, {:error, _} = error} ->
        error

      {:aborted, reason} ->
        Transaction.transaction_error(reason, module, "storing", :global, :database)
    end
  end

  # Reads one row under a write lock (by id directly, by an indexed field via its index then id)
  # and converts it to a struct, or `nil`. Must run inside a transaction.
  defp locked_read(module, :id, id) do
    :mnesia.read(module, id, :write)
    |> MnesiaAssistant.tuple_to_map(module.keys(), module, [])
    |> List.first()
  end

  defp locked_read(module, field, value) do
    case :mnesia.index_read(module, value, field) do
      [record | _] -> locked_read(module, :id, elem(record, 1))
      _ -> nil
    end
  end

  defp to_tuple(module, struct) do
    ([module] ++ Enum.map(module.keys(), &Map.get(struct, &1))) |> List.to_tuple()
  end
end
