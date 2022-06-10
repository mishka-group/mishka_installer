defmodule MishkaInstaller.Helper.Sender do
  @moduledoc """
    At first, we try to get basic information from `hex.pm` website; but after releasing some versions of MishkaInstaller,
    this API can be useful for managing packages from admin panel.

    **Ref: `https://github.com/hexpm/hexpm/issues/1124`**
  """
  @request_name HexClientApi
  alias MishkaInstaller.Helper.Extra

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
      {:ok, ast} -> Extra.ast_mix_file_basic_information(ast, [:app, :version, :source_url], [{:tag, tag}])
      _ -> {:error, :package, :mix_file}
    end
  end

  defp get_basic_information_form_github(output, _tag), do: output
end
