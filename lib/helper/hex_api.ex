defmodule MishkaInstaller.Helper.HexApi do
  @moduledoc """
    At first, we try to get basic information from `hex.pm` website; but after releasing some versions of MishkaInstaller,
    this API can be useful for managing packages from admin panel.

    **Ref: `https://github.com/hexpm/hexpm/issues/1124`**
  """
  @request_name HexClientApi

  @type app :: String.t()

  @spec package(app()) :: {:error, :package, :not_found | :unhandled} | {:ok, :package, map()}
  def package(app) do
    url = "https://hex.pm/api/packages/#{app}"
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
