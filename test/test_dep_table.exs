defmodule MishkaInstaller.Repo.Migrations.TestDepTable do
  use Ecto.Migration
  def change do
    create table(:dependencies, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:app, :string, size: 200, null: false)
      add(:version, :string, size: 200, null: false)
      add(:type, :integer, null: false)
      add(:dependency_type, :integer, null: false)

      add(:url, :text, null: true)
      add(:git_tag, :string, size: 200, null: true)
      add(:timeout, :integer, null: true)
      add(:update_server, :text, null: true)
      add(:dependencies, {:array, :map}, null: true)

      timestamps()
    end
    create(index(:dependencies, [:app], name: :index_dependencies_on_app, unique: true))
  end
end
