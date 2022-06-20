defmodule MishkaInstaller.Database.DependencySchema do
  use Ecto.Schema

  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dependencies" do
    field :app, :string
    field :version, :string
    field :type, MishkaInstaller.DependencyEnum
    field :dependency_type, MishkaInstaller.DependencyTypeEnum

    field :url, :string
    field :git_tag, :string
    field :custom_command, :string
    field :dependencies, {:array, :map}

    timestamps(type: :utc_datetime)
  end

  @all_fields ~w(app version type url dependency_type git_tag custom_command dependencies)a
  @required_fields ~w(app version type dependency_type)a

  @spec changeset(struct(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, @all_fields)
    |> validate_required(@required_fields, message: Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "You should fill all the required fields."))
    |> unique_constraint(:name, name: :index_dependencies_on_app, message: Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Each dependency should have a unique app name, this name existed before."))
  end
end
