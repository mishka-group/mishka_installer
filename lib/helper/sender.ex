defmodule MishkaInstaller.Helper.Sender do
  @moduledoc """
    At first, we try to get basic information from `hex.pm` website; but after releasing some versions of MishkaInstaller,
    this API can be useful for managing packages from admin panel.

    **Ref: `https://github.com/hexpm/hexpm/issues/1124`**
  """
  @request_name HexClientApi

  @type app :: map()

  @spec package(String.t(), app()) :: list | {:error, :package, :mix_file | :not_found | :not_tag | :unhandled} | {:ok, :package, any}
  def package("hex", %{"app" => name} = _app) do
    send_build(:get, "https://hex.pm/api/packages/#{name}")
  end

  def package("github", %{"url" => url, "tag" => tag} = _app) when not is_nil(url) and not is_nil(tag) do
    new_url = String.replace(String.trim(url), "https://github.com/", "https://raw.githubusercontent.com/") <> "/#{String.trim(tag)}/mix.exs"
    send_build(:get, new_url, :normal)
    |> get_basic_information_form_github(String.trim(tag))
  end

  def package(_status, _app), do: {:error, :package, :not_tag}

  defp send_build(:get, url, request \\ :json) do
    Finch.build(:get, url)
    |> Finch.request(@request_name)
    |> request_handler(request)
  end

  defp request_handler({:ok, %Finch.Response{body: body, headers: _headers, status: 200}}, :json) do
    {:ok, :package, Jason.decode!(body)}
  end

  defp request_handler({:ok, %Finch.Response{body: body, headers: _headers, status: 200}}, :normal) do
    {:ok, :package, body}
  end

  defp request_handler({:ok, %Finch.Response{status: 404}}, _), do: {:error, :package, :not_found}
  defp request_handler(_outputs, _), do: {:error, :package, :unhandled}

  defp get_basic_information_form_github({:ok, :package, body}, tag) do
    case Code.string_to_quoted(body) do
      {:ok, ast} -> ast_github_basic_information(ast, [:app, :version, :source_url], tag)
      _ -> {:error, :package, :mix_file}
    end
  end

  defp get_basic_information_form_github(output, _tag), do: output

  # Ref: https://elixirforum.com/t/getting-basic-information-of-a-elixir-project-from-github/48231/7
  defp ast_github_basic_information(ast, selection, tag) do
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
        convert_github_output(acc)
    end) ++ [{:tag, tag}]
  end

  # I duplicated the code to make this operation clear instead of getting dynamically and make it complicated.
  defp convert_github_output(%{version: {:attribute, item}, attributes: attributes}), do: {:version, List.first(Map.get(attributes, item))}
  defp convert_github_output(%{version: ver, attributes: _attributes}) when is_binary(ver), do: {:version, ver}
  defp convert_github_output(%{app: {:attribute, item}, attributes: attributes}), do: {:app, List.first(Map.get(attributes, item))}
  defp convert_github_output(%{app: ver, attributes: _attributes}) when is_atom(ver), do: {:app, ver}
  defp convert_github_output(%{source_url: {:attribute, item}, attributes: attributes}), do: {:source_url, List.first(Map.get(attributes, item))}
  defp convert_github_output(%{source_url: ver, attributes: _attributes}) when is_binary(ver), do: {:source_url, ver}
  defp convert_github_output(_), do: {:error, :package, :convert_github_output}
end
