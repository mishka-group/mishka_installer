defmodule MishkaInstaller.Installer.LibraryReader do
  # Based on https://github.com/mishka-group/mishka_installer/blob/master/lib/helper/library_maker.ex
  @doc """
  With this function, you can extract some basic information from a `mix` file by AST.

  ## Examples

  ```elixir
  alias MishkaInstaller.Installer.LibraryReader

  LibraryReader.ast_mix_file_basic_information(ast, [:app, :version, :source_url], [{:tag, tag}])
  ```

  ### Reference

  - https://elixirforum.com/t/48231/7
  """
  def ast_mix_file_basic_information(ast, selection, extra \\ []) do
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
