defmodule MishkaInstaller.Helper.Extra do
  # Ref: https://elixirforum.com/t/getting-basic-information-of-a-elixir-project-from-github/48231/7
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
        convert_ast_output(acc)
    end) ++ extra
  end

  # I duplicated the code to make this operation clear instead of getting dynamically and make it complicated.
  defp convert_ast_output(%{version: {:attribute, item}, attributes: attributes}), do: {:version, List.first(Map.get(attributes, item))}
  defp convert_ast_output(%{version: ver, attributes: _attributes}) when is_binary(ver), do: {:version, ver}
  defp convert_ast_output(%{app: {:attribute, item}, attributes: attributes}), do: {:app, List.first(Map.get(attributes, item))}
  defp convert_ast_output(%{app: ver, attributes: _attributes}) when is_atom(ver), do: {:app, ver}
  defp convert_ast_output(%{source_url: {:attribute, item}, attributes: attributes}), do: {:source_url, List.first(Map.get(attributes, item))}
  defp convert_ast_output(%{source_url: ver, attributes: _attributes}) when is_binary(ver), do: {:source_url, ver}
  defp convert_ast_output(_), do: {:error, :package, :convert_ast_output}
end
