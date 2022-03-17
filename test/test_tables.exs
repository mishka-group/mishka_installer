defmodule MishkaInstaller.Repo.Migrations.TestActivityTable do
  use Ecto.Migration
  def change do
    create table(:activities, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:type, :integer, null: false)
      add(:action, :integer, null: false)
      add(:section, :integer, null: false, null: false)
      add(:section_id, :uuid, primary_key: false, null: true)
      add(:priority, :integer, null: false)
      add(:status, :integer, null: false)
      add(:extra, :map, null: true)

      timestamps()
    end
  end
end

defmodule MishkaInstaller.Repo.Migrations.TestCategoryTable do
  use Ecto.Migration
  def change do
    create table(:plugins, primary_key: false)
      add(:id, :uuid, primary_key: true)
      add(:name, :string, size: 200, null: false)
      add(:event, :string, size: 200, null: false)
      add(:priority, :integer, null: false)
      add(:status, :integer, null: false)
      add(:depend_type, :integer, null: false)
      add(:depends, {:array, :string}, null: true)
      add(:extra, {:array, :map}, null: false)

      timestamps()
    end
    create(
      index(:plugins, [:name],
        name: :index_plugins_on_name,
        unique: true
      )
    )
  end
end
