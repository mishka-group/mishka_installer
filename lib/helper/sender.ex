defmodule MishkaInstaller.Helper.Sender do
  @moduledoc """
    At first, we try to get basic information from `hex.pm` website; but after releasing some versions of MishkaInstaller,
    this API can be useful for managing packages from admin panel.

    **Ref: `https://github.com/hexpm/hexpm/issues/1124`**
  """
  @request_name HexClientApi

  @type app :: map()

  @spec package(String.t(), app()) :: {:error, :package, :not_found | :unhandled} | {:ok, :package, map()}
  def package("hex", %{"app" => name} = _app) do
    send_build(:get, "https://hex.pm/api/packages/#{name}")
  end

  def package("git", %{"update_server" => url, "tag" => tag} = _app) when not is_nil(url) and not is_nil(tag) do
    send_build(:get, url)
  end

  def package(_status, _app), do: {:error, :package, :not_tag}

  defp send_build(:get, url) do
    Finch.build(:get, url)
    |> Finch.request(@request_name)
    |> request_handler()
  end

  defp request_handler({:ok, %Finch.Response{body: body, headers: _headers, status: 200}}) do
    {:ok, :package, Jason.decode!(body)}
  end

  defp request_handler({:ok, %Finch.Response{status: 404}}), do: {:error, :package, :not_found}
  defp request_handler(_outputs), do: {:error, :package, :unhandled}
end
