defmodule MishkaInstaller.Installer.RunTimeSourcing do
  @type ensure() :: :sure_all_started | :load

  @spec do_runtime_install(atom) :: {:ok, :application_ensure} | {:error, :application_ensure, ensure(), any}
  def do_runtime_install(app) do
    get_build_path()
    |> File.ls!()
    |> compare_dependencies()
    |> prepend_compiled_apps()
    application_ensure(app)
  end

  @spec compare_dependencies([tuple()], [String.t()]) :: [String.t()]
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

  @spec deps :: list
  def deps() do
    [{:get, "deps.get"}, {:compile, "deps.compile"}]
    |> Enum.map(fn {operation, command} ->
      {stream, status} = System.cmd("mix", [command], into: IO.stream())
      %{operation: operation, output: stream, status: status}
    end)
  end

  def prepend_compiled_apps([]), do: {:error, :prepend_compiled_apps, :no_directory}
  def prepend_compiled_apps(files_list) do
    files_list
    |> Enum.map(& {String.to_atom(&1), Path.join(get_build_path() <> "/" <> &1, "ebin")  |> Code.prepend_path})
    |> Enum.filter(fn {_app, status} -> status == {:error, :bad_directory} end)
    |> case do
      [] -> {:ok, :prepend_compiled_apps}
      list -> {:error, :prepend_compiled_apps, :bad_directory, list}
    end
  end

  defp get_build_path(mode \\ Mix.env()) do
    Path.join(MishkaInstaller.get_config(:project_path) || File.cwd!(), ["_build/", "#{mode}/", "lib"])
  end

  defp application_ensure(app) do
    with {:load, :ok} <- {:load, Application.load(app)},
         {:sure_all_started, {:ok, _apps}} <- {:sure_all_started, Application.ensure_all_started(app)} do

        {:ok, :application_ensure}
    else
      {:load, {:error, term}} -> {:error, :application_ensure, :load, term}
      {:sure_all_started, {:error, {app, term}}} -> {:error, :application_ensure, :sure_all_started, {app, term}}
    end
  end
end
