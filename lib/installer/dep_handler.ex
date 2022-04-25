defmodule MishkaInstaller.Installer.DepHandler do
  # TODO: Create a sample structuer to make json what fields shoud be existed
  # TODO: Where path is the place we have to save json
  # TODO: Create a function to read all dependencies from the json file created
  # TODO: Create a function to read information of a dep
  # TODO: Check if this file does not exist, create it with database
  # TODO: Read the installed_app information and existed app in json file, what sub-dependencies need to be updated
  # TODO: Create queue for installing multi deps, and compiling, check oban: https://github.com/sorentwo/oban
  # TODO: Add version of app in extra
  # TODO: Check is there update from a developer json url, and get it from plugin/componnet mix file, Consider queue
  # TODO: Check Conflict with max and mix dependencies, before update with installed or will be installed apps
  # [
  #   %{
  #     app: :mishka_installer,
  #     version: "0.0.2",
  #     type: :git, # :hex, if user upload elixir libraries (path), we should keep them in a temporary folder, and Docker should make it valume
  #     url: "https://github.com/mishka-group/mishka_installer", # if it is hex: https://hex.pm/packages/mishka_installer
  #     tag: "0.0.2", # we consider it when it is a git, and if does not exist we get master,
  #     timeout: 3000, # it can be a feature, How long does it take to start?
  #     dependency_type: :none, # :soft_update, When you use this, the RunTime sourcing check what dependencies you use in your program have a higher version
  #     #compared to the old source. it just notice admin there is a update, it does not force the source to be updated
  #     dependencies: [ # this part let mishka_installer to know can update or not dependencies of a app, we should consider a backup file
  #       %{app: :mishka_developer_tools, max: "0.0.2", min: "0.0.1"},
  #       %{app: :mishka_social, max: "0.0.2", min: "0.0.1"}
  #     ],
  #     update: "https://github.com/mishka-group/mishka_installer/blob/master/update.json", # Check is there a higher version?
  #   }
  # ]

  @spec check_or_create_deps_json(binary) :: {:ok, :check_or_create_deps_json, String.t()} | {:error, :check_or_create_deps_json, String.t()}
  def check_or_create_deps_json(project_path \\ MishkaInstaller.get_config(:project_path) || File.cwd!()) do
    with {:deployment_path, true} <- {:deployment_path, File.exists?(Path.join(project_path, ["deployment"]))},
         {:extensions_path, true} <- {:extensions_path, File.exists?(Path.join(project_path, ["deployment/", "extensions"]))},
         {:json_file, true} <- {:json_file, File.exists?(Path.join(project_path, ["deployment/", "extensions/", "extensions.json"]))} do

         {:ok, :check_or_create_deps_json, File.read!(Path.join(project_path, ["deployment/", "extensions/", "extensions.json"]))}
    else
      {:deployment_path, false} ->
        create_deps_json_directory(project_path, "deployment")
      {:extensions_path, false} ->
        create_deps_json_directory(project_path, "deployment/extensions")
      {:json_file, false} ->
        create_deps_json_file(project_path)
    end
  end

  defp create_deps_json_directory(project_path, folder_path) do
    case File.mkdir(Path.join(project_path, folder_path)) do
      :ok -> check_or_create_deps_json(project_path)
      {:error, :eacces} -> {:error, :check_or_create_deps_json, "You do not have sufficient access to create this directory. Please add it manually."}
      {:error, :enospc} -> {:error, :check_or_create_deps_json, "there is no space left on the device."}
      {:error, e} when e in [:eexist, :enoent, :enotdir] ->
        {:error, :check_or_create_deps_json, "Please contact plugin support when you encounter this error."}
    end
  end

  defp create_deps_json_file(project_path) do
    case File.open(Path.join(project_path, ["deployment/", "extensions/", "extensions.json"]), [:write]) do
      {:ok, file} ->
        IO.binwrite(file, Jason.encode!([]))
        File.close(file)
        check_or_create_deps_json(project_path)
      _error -> {:error, :check_or_create_deps_json, "You do not have sufficient access to create this file. Please add it manually."}
    end
  end
end
