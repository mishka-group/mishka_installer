defmodule MishkaInstaller.Database.SettingSchema do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "settings" do
    field(:name, :string)
    field(:configs, :map)

    timestamps(type: :utc_datetime)
  end

  @spec changeset(struct(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :configs])
    |> validate_required([:name, :configs], message: "You should fill all the required fields.")
    |> validate_length(:name, min: 5, max: 50, message: "Follow the maximum and minimum number of characters allowed.")
    |> unique_constraint(:section, name: :index_name_on_settings, message: "Each setting should have a unique name, this name existed before.")
  end
end
