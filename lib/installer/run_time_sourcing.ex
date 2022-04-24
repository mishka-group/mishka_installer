defmodule MishkaInstaller.Installer.RunTimeSourcing do
  def get_installed_apps() do

  end

  def compiled_apps(_mode \\ Mix.env()) do

  end

  def compare_dependencies(installed_apps \\ Application.loaded_applications, files_list) do
    installed_apps = Map.new(installed_apps, fn {app, _des, _ver} = item -> {Atom.to_string(app), item} end)
    Enum.map(files_list, fn app_name ->
      case Map.fetch(installed_apps, app_name) do
        :error ->
          app_name
        _ ->
          nil
        end
    end)
    |> Enum.reject(& is_nil(&1))
  end

  def deps() do
    [{:get, "deps.get"}, {:compile, "deps.compile"}]
    |> Enum.map(fn {operation, command} ->
      {stream, status} = System.cmd("mix", [command], into: IO.stream())
      %{operation: operation, output: stream, status: status}
    end)
  end

  def prepend_compiled_apps(files_list) do
    files_list
    |> Enum.map(& {String.to_atom(&1), Path.join(get_build_path() <> "/" <> &1, "ebin")  |> Code.prepend_path})
    |> Enum.filter(fn {_app, status} -> status == {:error, :bad_directory} end)
    |> case do
      [] -> {:ok, :prepend_compiled_apps}
      list -> {:error, :bad_directory, list}
    end
  end

  defp get_build_path(mode \\ Mix.env()) do
    Path.join(MishkaInstaller.get_config(:project_path) || File.cwd!(), ["_build/", "#{mode}/", "lib"])
  end
end
