defmodule MishkaInstaller.Database.SettingSchema do
  @moduledoc """
  This module has been implemented to create the `Settings` table schema.
  """

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
    |> validate_required([:name, :configs],
      message:
        Gettext.dgettext(
          MishkaInstaller.gettext(),
          "mishka_installer",
          "You should fill all the required fields."
        )
    )
    |> validate_length(:name,
      min: 5,
      max: 50,
      message:
        Gettext.dgettext(
          MishkaInstaller.gettext(),
          "mishka_installer",
          "Follow the maximum and minimum number of characters allowed."
        )
    )
    |> unique_constraint(:section,
      name: :index_name_on_settings,
      message:
        Gettext.dgettext(
          MishkaInstaller.gettext(),
          "mishka_installer",
          "Each setting should have a unique name, this name existed before."
        )
    )
  end
end
