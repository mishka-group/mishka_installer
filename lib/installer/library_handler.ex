defmodule MishkaInstaller.Installer.LibraryHandler do
  @moduledoc """

  """
  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  @type okey_return :: {:ok, struct() | map()}

  @type app :: String.t() | atom()

  @type runtime_type :: :add | :force_update | :uninstall

  @type compile_time_type :: :cmd | :port | :mix
  ####################################################################################
  ######################## (▰˘◡˘▰) Public API (▰˘◡˘▰) ##########################
  ####################################################################################
  @spec do_runtime(app, runtime_type) :: any()
  def do_runtime(_app, :add) do
  end

  def do_runtime(_app, :force_update) do
  end

  def do_runtime(_app, :uninstall) do
  end

  @spec do_runtime(app, compile_time_type) :: any()
  def do_compile_time(_app, type) when type in [:cmd, :port, :mix] do
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

  # TODO: should be changed
  # erl_tar:extract("rel/project-1.0.tar.gz", [compressed]);
  @spec extract(:tar, String.t()) :: {:error, :extract} | {:ok, :extract}
  def extract(:tar, archived_file) do
    extract_output =
      :erl_tar.extract(
        ~c'#{extensions_path()}/#{archived_file}.tar.gz',
        [:compressed, {:cwd, ~c'#{extensions_path()}/#{archived_file}'}]
      )

    case extract_output do
      :ok -> {:ok, :extract}
      {:error, term} -> {:error, :extract, term}
    end
  end

  # TODO: should be changed
  @spec checksum(String.t(), integer()) :: String.t()
  def checksum(file_path, size \\ 2048) do
    File.stream!(file_path, size)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn line, acc -> :crypto.hash_update(acc, line) end)
    |> :crypto.hash_final()
    |> Base.encode16()
    |> String.downcase()
  end

  # TODO: should be changed
  @spec checksum?(map()) :: boolean()
  def checksum?(app_info) do
    "#{extensions_path()}/#{Map.get(app_info, :app)}-#{Map.get(app_info, :version)}.tar.gz"
    |> checksum()
    |> Kernel.==(Map.get(app_info, :checksum))
  end

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

  # TODO: should be changed
  defp extensions_path() do
    Path.join("project_path", ["deployment/", "extensions"])
  end
end
