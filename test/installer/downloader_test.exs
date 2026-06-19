defmodule MishkaInstallerTest.Installer.DownloaderTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Installer.Downloader

  setup do
    Application.put_env(:mishka_installer, :downloader_req_options, plug: {Req.Test, Downloader})
    :ok
  end

  describe "Download pre-built artifact Mock Test ===>" do
    test "Download a direct artifact URL (:url) returns the raw tarball bytes" do
      tarball = :crypto.strong_rand_bytes(64)
      stub_binary(tarball)

      {:ok, body} =
        assert Downloader.download(:url, %{path: "https://cdn.example.com/app.tar.gz"})

      assert body == tarball
    end

    test "Download a non-200 URL returns an error" do
      Req.Test.stub(Downloader, fn conn -> Plug.Conn.send_resp(conn, 404, "nope") end)

      {:error, [%{action: :download}]} =
        assert Downloader.download(:url, %{path: "https://cdn.example.com/missing.tar.gz"})
    end

    test "Download the latest GitHub release resolves the asset then downloads it" do
      tarball = :crypto.strong_rand_bytes(48)
      stub_release_then_binary(tarball)

      {:ok, body} = assert Downloader.download(:github_latest_release, %{path: "owner/repo"})
      assert body == tarball
    end

    test "Download a specific GitHub tag resolves the named asset" do
      tarball = :crypto.strong_rand_bytes(32)
      stub_release_then_binary(tarball, "app-ebin.tar.gz")

      {:ok, body} =
        assert Downloader.download(:github_tag, %{
                 path: "owner/repo",
                 tag: "0.1.0",
                 asset: "app-ebin.tar.gz"
               })

      assert body == tarball
    end

    test "A release with no assets is an error" do
      Req.Test.stub(Downloader, fn conn -> Req.Test.json(conn, %{"assets" => []}) end)

      {:error, [%{action: :download}]} =
        assert Downloader.download(:github_latest_release, %{path: "owner/repo"})
    end

    test "An unknown download type is an error" do
      {:error, [%{action: :download}]} = assert Downloader.download(:hex, %{app: "whatever"})
    end
  end

  defp stub_binary(tarball) do
    Req.Test.stub(Downloader, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/gzip", nil)
      |> Plug.Conn.send_resp(200, tarball)
    end)
  end

  # First request (GitHub API) -> JSON with assets; any other request -> the raw tarball bytes.
  defp stub_release_then_binary(tarball, asset_name \\ "app.tar.gz") do
    Req.Test.stub(Downloader, fn conn ->
      if String.contains?(conn.request_path, "/releases") do
        Req.Test.json(conn, %{
          "assets" => [
            %{
              "name" => asset_name,
              "browser_download_url" => "https://cdn.example.com/#{asset_name}"
            }
          ]
        })
      else
        conn
        |> Plug.Conn.put_resp_content_type("application/gzip", nil)
        |> Plug.Conn.send_resp(200, tarball)
      end
    end)
  end
end
