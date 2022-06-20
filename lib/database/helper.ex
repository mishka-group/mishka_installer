defmodule MishkaInstaller.Database.Helper do
  import Ecto.Changeset
  require Logger

  @spec translate_errors(Ecto.Changeset.t()) :: %{optional(atom) => [binary | map]}
  def translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
    end)
  end

  @spec convert_string_map_to_atom_map(map) :: map
  def convert_string_map_to_atom_map(map) do
    map
    |> Map.new(fn {k, v} ->
        {String.to_existing_atom(k), v}
    end)
  end

  @spec validate_binary_id(Ecto.Changeset.t(), atom, any) :: Ecto.Changeset.t()
  def validate_binary_id(changeset, field, options \\ []) do
    validate_change(changeset, field, fn _, uuid ->
      case uuid(uuid) do
        {:ok, :uuid, _record_id} -> []
        {:error, :uuid} -> [{field, options[:message] || Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "ID should be as a UUID type.")}]
      end
    end)
  end

  @spec uuid(any) :: {:error, :uuid} | {:ok, :uuid, Ecto.UUID.t}
  def uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, record_id} -> {:ok, :uuid, record_id}
      _ -> {:error, :uuid}
    end
  end

  # Ref: https://elixirforum.com/t/how-to-send-sandbox-allow-for-each-dynamic-supervisor-testing/46422/4
  def allow_if_sandbox(parent_pid, orphan_msg \\ :stop) do
    if sandbox_pool?() do
      monitor_parent(parent_pid, orphan_msg)
      # this addresses #1
      Ecto.Adapters.SQL.Sandbox.allow(MishkaInstaller.repo, parent_pid, self())
    end
  end

  def sandbox_pool?() do
    MishkaInstaller.repo == Ecto.Integration.TestRepo
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

  def get_parent_pid(state) when is_nil(state.parent_pid), do: :ok

  def get_parent_pid(state) do
    if Mix.env() == :test do
      allow_if_sandbox(state.parent_pid)
    else
      :ok
    end
  end

end
