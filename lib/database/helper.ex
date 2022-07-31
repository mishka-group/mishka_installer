defmodule MishkaInstaller.Database.Helper do
  @moduledoc """
  This module provides some functions as utility tools to work with a database and other things.
  """

  import Ecto.Changeset
  require Logger

  @doc """
  If you need to convert database errors into a list, this function can be helpful.
  One of its uses can be correcting returned errors from the database into a list and converting it into JSON.

  ## Examples

  ```elixir
  MishkaInstaller.Database.Helper.translate_errors(changeset)
  ```
  """
  @spec translate_errors(Ecto.Changeset.t()) :: %{optional(atom) => [binary | map]}
  def translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc """
  Converting string map to atom map.

  ## Examples

  ```elixir
  MishkaInstaller.Database.Helper.convert_string_map_to_atom_map(%{"name" => "Mishka"})
  ```
  """
  @spec convert_string_map_to_atom_map(map) :: map
  def convert_string_map_to_atom_map(map) do
    map
    |> Map.new(fn {k, v} ->
      {String.to_existing_atom(k), v}
    end)
  end

  @doc """
  UUID validation for ecto schema.

  ## Examples

  ```elixir
  MishkaInstaller.Database.Helper.validate_binary_id(12)
  # OR
  MishkaInstaller.Database.Helper.validate_binary_id("8c512ac2-e002-4589-a93f-b479e46c249d")
  ```
  """
  @spec validate_binary_id(Ecto.Changeset.t(), atom, any) :: Ecto.Changeset.t()
  def validate_binary_id(changeset, field, options \\ []) do
    validate_change(changeset, field, fn _, uuid ->
      case uuid(uuid) do
        {:ok, :uuid, _record_id} ->
          []

        {:error, :uuid} ->
          [
            {field,
             options[:message] ||
               Gettext.dgettext(
                 MishkaInstaller.gettext(),
                 "mishka_installer",
                 "ID should be as a UUID type."
               )}
          ]
      end
    end)
  end

  @doc """
  UUID validation.

  ## Examples

  ```elixir
  MishkaInstaller.Database.Helper.uuid(12)
  # OR
  MishkaInstaller.Database.Helper.uuid("8c512ac2-e002-4589-a93f-b479e46c249d")
  ```
  """
  @spec uuid(any) :: {:error, :uuid} | {:ok, :uuid, Ecto.UUID.t()}
  def uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, record_id} -> {:ok, :uuid, record_id}
      _ -> {:error, :uuid}
    end
  end

  @doc """
  Helper function to keep PID alive for testing Genserver and database.

  ### Reference
  - https://elixirforum.com/t/how-to-send-sandbox-allow-for-each-dynamic-supervisor-testing/46422/4

  ## Examples

  ```elixir
  MishkaInstaller.Database.Helper.allow_if_sandbox(pid)
  ```
  """
  def allow_if_sandbox(parent_pid, orphan_msg \\ :stop) do
    if sandbox_pool?() do
      monitor_parent(parent_pid, orphan_msg)
      # this addresses #1
      Ecto.Adapters.SQL.Sandbox.allow(MishkaInstaller.repo(), parent_pid, self())
    end
  end

  defp sandbox_pool?() do
    MishkaInstaller.repo() == Ecto.Integration.TestRepo
  end

  defp monitor_parent(parent_pid, orphan_msg) do
    # this is part of addressing #2
    Process.monitor(parent_pid)

    if Process.alive?(parent_pid) do
      :ok
    else
      Logger.error("#{inspect(parent_pid)} down when booting #{inspect(self())}")
      # this addresses #3
      # the "throw" will work like an early "return"; see the GenServer docs
      throw(orphan_msg)
    end
  end

  @doc false
  def get_parent_pid(state) when is_nil(state.parent_pid), do: :ok

  def get_parent_pid(state) do
    if Mix.env() == :test do
      allow_if_sandbox(state.parent_pid)
    else
      :ok
    end
  end
end
