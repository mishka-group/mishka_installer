defmodule MishkaInstaller.Installer.LibraryHandler do
  @moduledoc """

  """
  alias MishkaInstaller.Installer.Installer

  @type posix :: :file.posix()

  @type io_device :: :file.io_device()

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  @type okey_return :: {:ok, struct() | map() | binary()}

  @type app :: Installer.t()

  @type runtime_type :: :add | :force_update | :uninstall

  @type compile_time_type :: :cmd | :port | :mix

  ####################################################################################
  ######################## (▰˘◡˘▰) Public API (▰˘◡˘▰) ##########################
  ####################################################################################
  @spec do_runtime(app, runtime_type) :: any()
  def do_runtime(%Installer{} = _app, :add) do
  end

  def do_runtime(%Installer{} = _app, :force_update) do
  end

  def do_runtime(%Installer{} = _app, :uninstall) do
  end

  @spec do_runtime(app, compile_time_type) :: any()
  def do_compile_time(%Installer{} = _app, type) when type in [:cmd, :port, :mix] do
  end

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @spec compare_dependencies([tuple()], [String.t()]) :: [String.t()]
  def compare_dependencies(installed_apps \\ Application.loaded_applications(), files_list) do
    installed_apps =
      Map.new(installed_apps, fn {app, _des, _ver} = item -> {Atom.to_string(app), item} end)

    Enum.reduce(files_list, [], fn app_name, acc ->
      if Map.fetch(installed_apps, app_name) == :error, do: acc ++ [app_name], else: acc
    end)
  end

  def get_basic_information_from_mix_ast(ast, selection, extra \\ []) do
    Enum.map(selection, fn item ->
      {_ast, acc} =
        Macro.postwalk(ast, %{"#{item}": nil, attributes: %{}}, fn
          {:@, _, [{name, _, value}]} = ast, acc when is_atom(name) and not is_nil(value) ->
            {ast, put_in(acc.attributes[name], value)}

          {^item, {:@, _, [{name, _, nil}]}} = ast, acc ->
            {ast, Map.put(acc, item, {:attribute, name})}

          {^item, value} = ast, acc ->
            {ast, Map.put(acc, item, value)}

          ast, acc ->
            {ast, acc}
        end)

      convert_mix_ast_output(acc)
    end) ++ extra
  end

  @spec extract(:tar, binary(), String.t()) :: :ok | error_return()
  def extract(:tar, archived, name) do
    temp_path = ~c'#{extensions_path()}/temp-#{name}'

    :erl_tar.extract(~c'#{archived}', [:compressed, {:cwd, ~c'#{temp_path}'}])
    |> case do
      :ok ->
        files_list = File.ls!(temp_path)

        if "mix.exs" in files_list do
          File.rename(temp_path, ~c'#{extensions_path()}/#{name}')
          :ok
        else
          dirs_list =
            File.ls!(temp_path)
            |> Enum.filter(&File.dir?("#{extensions_path()}/temp-#{name}/#{&1}"))

          finding_mix =
            Enum.find(
              dirs_list,
              &("mix.exs" in File.ls!("#{extensions_path()}/temp-#{name}/#{&1}"))
            )

          if is_nil(finding_mix) do
            message =
              "There is a problem in extracting the compressed file of the ready-made library."

            {:error,
             [%{message: message, field: :path, action: :extract, source: :bad_structure}]}
          else
            temp_file_path = "#{extensions_path()}/temp-#{name}/#{finding_mix}"

            case File.rename(temp_file_path, "#{extensions_path()}/#{name}") do
              :ok ->
                File.rm_rf!("#{extensions_path()}/temp-#{name}")
                :ok

              {:error, source} ->
                File.rm_rf!("#{extensions_path()}/temp-#{name}")
                message = "There was a problem moving the file."
                {:error, [%{message: message, field: :path, action: :extract, source: source}]}
            end
          end
        end

      {:error, term} ->
        message =
          "There is a problem in extracting the compressed file of the ready-made library."

        {:error, [%{message: message, field: :path, action: :move, source: term}]}
    end
  end

  @spec move(Installer.t(), binary()) :: okey_return() | error_return()
  def move(app, archived_file) do
    with {:mkdir_p, :ok} <- {:mkdir_p, File.mkdir_p(extensions_path())},
         {:ok, path} <- write_downloaded_lib(app, archived_file) do
      {:ok, path}
    else
      {:mkdir_p, {:error, error}} ->
        message = "An error occurred in downloading and transferring the library file you want."
        {:error, [%{message: message, field: :path, action: :move, source: error}]}

      error ->
        error
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Callback (▰˘◡˘▰) ##########################
  ####################################################################################

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  # I duplicated the code to make this operation clear instead of getting dynamically and make it complicated.
  defp convert_mix_ast_output(%{version: {:attribute, item}, attributes: attributes}),
    do: {:version, List.first(Map.get(attributes, item))}

  defp convert_mix_ast_output(%{version: ver, attributes: _attributes}) when is_binary(ver),
    do: {:version, ver}

  defp convert_mix_ast_output(%{app: {:attribute, item}, attributes: attributes}),
    do: {:app, List.first(Map.get(attributes, item))}

  defp convert_mix_ast_output(%{app: ver, attributes: _attributes}) when is_atom(ver),
    do: {:app, ver}

  defp convert_mix_ast_output(%{source_url: {:attribute, item}, attributes: attributes}),
    do: {:source_url, List.first(Map.get(attributes, item))}

  defp convert_mix_ast_output(%{source_url: ver, attributes: _attributes}) when is_binary(ver),
    do: {:source_url, ver}

  defp convert_mix_ast_output(_), do: {:error, :package, :convert_mix_ast_output}

  defp write_downloaded_lib(app, archived_file) do
    open_file =
      File.open("#{extensions_path()}/#{app.app}-#{app.version}.tar", [:read, :write], fn file ->
        IO.binwrite(file, archived_file)
        File.close(file)
      end)

    case open_file do
      {:ok, _ress} ->
        {:ok, "#{extensions_path()}/#{app.app}-#{app.version}.tar"}

      error ->
        message = "An error occurred in downloading and transferring the library file you want."
        {:error, [%{message: message, field: :path, action: :move, source: error}]}
    end
  end

  # TODO: should be changed
  def extensions_path() do
    info = MishkaInstaller.__information__()
    Path.join(info.path, ["deployment/", "#{info.env}/", "extensions"])
  end
end
