defmodule MishkaInstallerTest.Helper.RecordTest do
  use ExUnit.Case, async: true
  alias MishkaInstaller.Helper.Record
  alias MishkaInstaller.Installer.Installer
  alias MishkaInstaller.Event.Event

  describe "database_config/2 ===>" do
    test "describes a :set of the module's keys, kept in ram_copies when compiled for test" do
      config = Record.database_config(Installer, [:app])

      assert config[:type] == :set
      assert config[:index] == [:app]
      assert config[:record_name] == Installer
      assert config[:attributes] == Installer.keys()

      assert config[:storage_properties] == [
               ets: [read_concurrency: true, write_concurrency: true]
             ]

      assert config[:ram_copies] == [node()]
      refute Keyword.has_key?(config, :disc_copies)
    end

    test "is what Installer and Event hand to the table creation" do
      assert Installer.database_config() == Record.database_config(Installer, [:app])

      assert Event.database_config() ==
               Record.database_config(Event, [:name, :event, :extension])

      assert Event.database_config()[:index] == [:name, :event, :extension]
    end
  end

  describe "unique/2 ===>" do
    test "a record that is not there is unique" do
      assert Record.unique(nil, "library") == :ok
    end

    test "a record that is there is not, and the message names the record" do
      assert {:error, [%{field: :global, action: :unique, message: message}]} =
               Record.unique(%{id: "1"}, "library")

      assert message == "This library already exists in the database."
    end
  end

  describe "delete/2 ===>" do
    test "nothing selected is the error of a record that is incorrect or already deleted" do
      assert {:error, [%{field: :global, action: :delete, message: message}]} =
               Record.delete(Installer, nil)

      assert message =~ "incorrect or has already been deleted"
    end
  end
end
