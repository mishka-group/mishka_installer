defmodule MishkaInstaller.Installer.RunTimeSourcing do
  @moduledoc """
  This module is created just for compiling and sourcing, hence if you want to work with Json file and the other compiling dependencies
  please see the `MishkaInstaller.Installer.DepHandler` module.
  """

  @type ensure() :: :bad_directory | :load | :no_directory | :sure_all_started
  @type do_runtime() :: :application_ensure | :prepend_compiled_apps

  @spec do_runtime(atom(), atom()) ::{:ok, :application_ensure} | {:error, do_runtime(), ensure(), any}
  def do_runtime(app, :add) do
    get_build_path()
    |> File.ls!()
    |> compare_dependencies()
    |> prepend_compiled_apps()
    |> application_ensure(app)
  end

  def do_runtime(_app, :soft_update) do
    # TODO: update an installed app
    get_build_path()
    |> File.ls!()
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
      {stream, status} = System.cmd("mix", [command], into: IO.stream(), stderr_to_stdout: true)
      %{operation: operation, output: stream, status: status}
    end)
  end

  @spec prepend_compiled_apps(any) :: {:ok, :prepend_compiled_apps} | {:error, do_runtime(), ensure(), list}
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

  defp application_ensure({:ok, :prepend_compiled_apps}, app) do
    with {:load, :ok} <- {:load, Application.load(app)},
         {:sure_all_started, {:ok, _apps}} <- {:sure_all_started, Application.ensure_all_started(app)} do

        {:ok, :application_ensure}
    else
      {:load, {:error, term}} -> {:error, :application_ensure, :load, term}
      {:sure_all_started, {:error, {app, term}}} -> {:error, :application_ensure, :sure_all_started, {app, term}}
    end
  end

  defp application_ensure(error, _app), do: error
end
