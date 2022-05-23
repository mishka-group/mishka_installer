defmodule MishkaInstaller.Database.PluginSchema do
  use Ecto.Schema

  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "plugins" do
    field :name, :string
    field :event, :string
    field :priority, :integer
    field :status, MishkaInstaller.PluginStatusEnum, default: :started
    field :depend_type, MishkaInstaller.PluginDependTypeEnum, default: :soft
    field :depends, {:array, :string}
    field :extra, {:array, :map}

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
