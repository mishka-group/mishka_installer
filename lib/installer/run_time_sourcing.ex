defmodule MishkaInstaller.Installer.RunTimeSourcing do
  @moduledoc """
  This module is created just for compiling and sourcing, hence if you want to work with Json file and the other compiling dependencies
  please see the `MishkaInstaller.Installer.DepHandler` module.
  """

  @type ensure() :: :bad_directory | :load | :no_directory | :sure_all_started
  @type do_runtime() :: :application_ensure | :prepend_compiled_apps

  @spec do_runtime(atom(), atom()) ::{:ok, :application_ensure} | {:error, do_runtime(), ensure(), any}
  def do_runtime(app, :add) when is_atom(app) do
    get_build_path()
    |> File.ls!()
    |> compare_dependencies()
    |> prepend_compiled_apps()
    |> application_ensure(app, :add)
  end

  def do_runtime(app, :force_update) when is_atom(app) do
    if(Atom.to_string(app) in File.ls!(get_build_path()), do: ["#{app}"], else: false)
    |> prepend_compiled_apps()
    |> application_ensure(app, :force_update)
  end

  def do_runtime(app, :uninstall) when is_atom(app) do
    Application.stop(app)
    Application.unload(app)
    if(Atom.to_string(app) in File.ls!(get_build_path()), do: "#{app}", else: false)
    |> delete_app_dir()
  end

  defp delete_app_dir(false), do: {:error, :prepend_compiled_apps, :no_directory, []}
  defp delete_app_dir(dir) do
    Path.join(get_build_path(), ["#{dir}"])
    |> File.rm_rf()
    |> case do
      {:ok, files_and_directories} -> {:ok, :delete_app_dir, files_and_directories}
      {:error, reason, file} -> {:error, :delete_app_dir, reason, file}
    end
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

  @spec do_deps_compile(String.t()) :: {:ok, :do_deps_compile, String.t()}| {:error, :do_deps_compile, String.t(), [{:operation, String.t()} | {:output, any}]}
  def do_deps_compile(app) do
    # I delete the File.cwd!() as a default path because we need to back again, and it needs many conditions especially in DDD project
    with _cd_path <- File.cd(MishkaInstaller.get_config(:project_path)),
         %{operation: "deps.get", output: _stream, status: 0} <- cmd("deps.get"),
         deps_path <- Path.join(MishkaInstaller.get_config(:project_path), ["deps/", "#{app}"]),
         {:change_dir, :ok} <- {:change_dir, File.cd(deps_path)},
         {:inside_app, %{operation: "deps.get", output: _stream, status: 0}} <- {:inside_app, cmd("deps.get")},
         %{operation: "deps.compile", output: _stream, status: 0} <- cmd("deps.compile") do
      {:ok, :do_deps_compile, app}
    else
      %{operation: "deps.get", output: stream, status: 1} -> {:error, :do_deps_compile, app, operation: "deps.get", output: stream}
      {:inside_app, %{operation: "deps.get", output: stream, status: 1} }-> {:error, :do_deps_compile, app, operation: "deps.get", output: stream}
      {:change_dir, file_error} -> {:error, :do_deps_compile, app, operation: "File.cd", output: file_error}
      %{operation: "deps.compile", output: stream, status: 1} -> {:error, :do_deps_compile, app, operation: "deps.compile", output: stream}
      _ -> {:error, :do_deps_compile, app, operation: "File.cd", output: "Wrong path"}
    end
  after
    # Maybe a developer does not consider changed-path, so for preventing issues we back to the project path after each compiling
    File.cd(MishkaInstaller.get_config(:project_path))
  end

  @spec prepend_compiled_apps(any) :: {:ok, :prepend_compiled_apps} | {:error, do_runtime(), ensure(), list}
  def prepend_compiled_apps(false), do: {:error, :prepend_compiled_apps, :no_directory, []}
  def prepend_compiled_apps([]), do: {:error, :prepend_compiled_apps, :no_directory, []}
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

  defp application_ensure({:ok, :prepend_compiled_apps}, app, :add) do
    with {:load, :ok} <- {:load, Application.load(app)},
         {:sure_all_started, {:ok, _apps}} <- {:sure_all_started, Application.ensure_all_started(app)} do

        {:ok, :application_ensure}
    else
      {:load, {:error, term}} -> {:error, :application_ensure, :load, term}
      {:sure_all_started, {:error, {app, term}}} -> {:error, :application_ensure, :sure_all_started, {app, term}}
    end
  end

  defp application_ensure({:ok, :prepend_compiled_apps}, app, :force_update) do
    Application.stop(app)
    with {:unload, :ok} <- {:unload, Application.unload(app)},
         {:load, :ok} <- {:load, Application.load(app)},
         {:sure_all_started, {:ok, _apps}} <- {:sure_all_started, Application.ensure_all_started(app)} do

        {:ok, :application_ensure}
    else
      {:unload, {:error, term}} -> {:error, :application_ensure, :unload, term}
      {:load, {:error, term}} -> {:error, :application_ensure, :load, term}
      {:sure_all_started, {:error, {app, term}}} -> {:error, :application_ensure, :sure_all_started, {app, term}}
    end
  end

  defp application_ensure(error, _app, _status), do: error

  defp cmd(command, operation \\ "mix") do
    {stream, status} = System.cmd(operation, [command], into: IO.stream(), stderr_to_stdout: true)
    %{operation: command, output: stream, status: status}
  end
end
