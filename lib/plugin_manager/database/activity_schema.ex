defmodule MishkaInstaller.Database.ActivitySchema do
  use Ecto.Schema

  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "activities" do
    field(:type, MishkaInstaller.ActivitiesTypeEnum, null: false)
    field(:section, MishkaInstaller.ActivitiesSectionEnum, null: false)
    field(:section_id, :binary_id, primary_key: false, null: true)
    field(:priority, MishkaInstaller.ContentPriorityEnum, null: false)
    field(:status, MishkaInstaller.ActivitiesStatusEnum, null: false)
    field(:action, MishkaInstaller.ActivitiesActionEnum, null: false)
    field(:extra, :map, null: true)

    timestamps(type: :utc_datetime)
  end

  @all_fields ~w(type section section_id priority status action extra)a
  @all_required ~w(type section priority status action)a

  @spec changeset(struct(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, @all_fields)
    |> validate_required(@all_required, message: "You should fill all the required fields.")
    |> MishkaInstaller.Database.Helper.validate_binary_id(:section_id)
  end

end
