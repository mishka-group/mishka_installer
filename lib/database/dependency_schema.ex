defmodule MishkaInstaller.Database.DependencySchema do
  use Ecto.Schema

  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dependencies" do
    field :app, :string, null: false
    field :version, :string, null: false
    field :type, MishkaInstaller.DependencyEnum, null: false
    field :dependency_type, MishkaInstaller.DependencyTypeEnum, null: false

    field :url, :string, null: true
    field :git_tag, :string, null: true
    field :custom_command, :string, null: true
    field :update_server, :string, null: true
    field :dependencies, {:array, :map}, null: true

    timestamps(type: :utc_datetime)
  end

  @all_fields ~w(app version type url dependency_type git_tag custom_command update_server dependencies)a
  @required_fields ~w(app version type dependency_type)a

  @spec changeset(struct(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, @all_fields)
    |> validate_required(@required_fields, message: "You should fill all the required fields.")
    |> unique_constraint(:name, name: :index_dependencies_on_app, message: "Each dependency should have a unique app name, this name existed before.")
  end
end
