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
  alias MishkaInstaller.Helper.MnesiaAssistant
  alias MishkaInstaller.Helper.MnesiaAssistant.{Query, Transaction}

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
end
