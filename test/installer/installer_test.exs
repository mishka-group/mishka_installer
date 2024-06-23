defmodule MishkaInstallerTest.Installer.InstallerTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Installer.Installer

  setup do
    tmp_dir = System.tmp_dir!()

    mnesia_dir =
      "#{Path.join(tmp_dir, "mishka-installer-#{MishkaDeveloperTools.Helper.UUID.generate()}")}"

    on_exit(fn ->
      pid = Process.whereis(MishkaInstaller.MnesiaRepo)

      if !is_nil(pid) and Process.alive?(pid) do
        GenServer.stop(MishkaInstaller.MnesiaRepo)
      end
    end)

    Process.register(self(), :__mishka_installer_test__)

    Application.put_env(:mishka, Mishka.MnesiaRepo,
      mnesia_dir: mnesia_dir,
      essential: [Installer]
    )

    MishkaInstaller.subscribe("mnesia")

    start_supervised!(MishkaInstaller.MnesiaRepo)

    assert_receive %{status: :synchronized, channel: "mnesia", data: _data}

    :ok
  end

  ###################################################################################
  ########################## (▰˘◡˘▰) QueryTest (▰˘◡˘▰) ########################
  ###################################################################################
  describe "Installer Table CRUD QueryTest ===>" do
    test "Create a Library record" do
      {:error, _error} = assert Installer.write(%{})

      {:ok, _data} =
        assert Installer.write(%{
                 app: "mishka_developer_tools",
                 version: "0.1.5",
                 tag: "0.1.5",
                 type: :hex,
                 path: "mishka_developer_tools"
               })
    end

    test "Read a Library/Libraries records" do
      assert Installer.get() == []

      {:ok, _data} =
        assert Installer.write(%{
                 app: "mishka_developer_tools",
                 version: "0.1.5",
                 tag: "0.1.5",
                 type: :hex,
                 path: "mishka_developer_tools"
               })

      assert Installer.get() != []

      assert !is_nil(Installer.get(:app, "mishka_developer_tools"))
    end

    test "Update a Library record" do
      {:ok, _data} =
        assert Installer.write(%{
                 app: "mishka_developer_tools",
                 version: "0.1.5",
                 tag: "0.1.5",
                 type: :hex,
                 path: "mishka_developer_tools"
               })

      get_data = Installer.get() |> List.first()

      {:ok, struct} =
        assert Installer.write({:root, Map.merge(get_data, %{version: "0.1.6"}), :edit})

      assert struct.version == "0.1.6"
      get_data1 = Installer.get() |> List.first()
      assert get_data1.id == get_data.id
      {:ok, struct} = assert Installer.write(:id, get_data.id, %{type: :github})
      assert Installer.get(struct.id).type == :github
    end

    test "All keys of Libraries Record" do
      {:ok, _data} =
        assert Installer.write(%{
                 app: "mishka_developer_tools",
                 version: "0.1.5",
                 tag: "0.1.5",
                 type: :hex,
                 path: "mishka_developer_tools"
               })

      assert length(Installer.ids()) == 1
    end

    test "Unique? Library Record by app" do
      {:ok, _data} =
        assert Installer.write(%{
                 app: "mishka_developer_tools",
                 version: "0.1.5",
                 tag: "0.1.5",
                 type: :hex,
                 path: "mishka_developer_tools"
               })

      assert !is_nil(Installer.get(:app, "mishka_developer_tools"))
      assert is_nil(Installer.get(:app, "mishka_developer_tools1"))
    end

    test "Delete Library Record" do
      {:ok, _data} =
        assert Installer.write(%{
                 app: "mishka_developer_tools",
                 version: "0.1.5",
                 tag: "0.1.5",
                 type: :hex,
                 path: "mishka_developer_tools"
               })

      assert Installer.get() != []
      {:ok, _data} = Installer.delete(:app, "mishka_developer_tools")
      assert Installer.get() == []
    end

    test "Drop all Library records" do
      {:ok, _data} =
        assert Installer.write(%{
                 app: "mishka_developer_tools",
                 version: "0.1.5",
                 tag: "0.1.5",
                 type: :hex,
                 path: "mishka_developer_tools"
               })

      assert Installer.get() != []
      {:ok, :atomic} = assert Installer.drop()
      assert Installer.get() == []
    end
  end

  ###################################################################################
  ######################## (▰˘◡˘▰) FunctionsTest (▰˘◡˘▰) ######################
  ###################################################################################
  describe "Installer Module FunctionsTest ===>" do
  end
end
