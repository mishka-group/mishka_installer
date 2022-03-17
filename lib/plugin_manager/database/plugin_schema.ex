defmodule MishkaInstaller.Database.PluginSchema do
  use Ecto.Schema

  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "plugins" do
    field :name, :string, null: false
    field :event, :string, null: false
    field :priority, :integer, null: false
    field :status, MishkaInistaller.PluginStatusEnum, null: false, default: :started
    field :depend_type, MishkaInistaller.PluginDependTypeEnum, null: false, default: :soft
    field :depends, {:array, :string}, null: true
    field :extra, {:array, :map}, null: false

    timestamps(type: :utc_datetime)
  end

  @all_fields ~w(name event priority status depend_type depends extra)a
  @required_fields ~w(name event priority status depend_type)a

  @spec changeset(struct(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, @all_fields)
    |> validate_required(@required_fields, message: "You should fill all the required fields.")
    |> unique_constraint(:name, name: :index_plugins_on_name, message: "Each plugin should have a unique name, this name existed before.")
  end

end
