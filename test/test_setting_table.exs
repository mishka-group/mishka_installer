defmodule MishkaInstaller.Repo.Migrations.TestSettingTable do
  use Ecto.Migration
  def change do
    create table(:settings, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string, size: 50, null: false)
      add(:configs, :map, null: false)

      timestamps()
    end
    create(index(:settings, [:name], name: :index_name_on_settings, unique: true))
  end
end
