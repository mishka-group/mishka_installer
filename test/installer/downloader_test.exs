defmodule MishkaInstallerTest.Installer.DownloaderTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Installer.Downloader

  setup do
    Application.put_env(:mishka_installer, :downloader_req_options, plug: {Req.Test, Downloader})
    on_exit(fn -> Application.delete_env(:mishka_installer, :allowlist) end)
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

  describe "Redirects ===>" do
    test "a redirect to a host that is not allowed is refused and never requested" do
      tarball = :crypto.strong_rand_bytes(16)
      test_pid = self()

      Req.Test.stub(Downloader, fn conn ->
        send(test_pid, {:requested, conn.host})

        case conn.host do
          "cdn.example.com" -> redirect(conn, "https://other-host.example/evil.tar.gz")
          _ -> binary_response(conn, tarball)
        end
      end)

      {:error, [%{action: :download}]} =
        assert Downloader.download(:url, %{path: "https://cdn.example.com/app.tar.gz"})

      assert_received {:requested, "cdn.example.com"}
      refute_received {:requested, "other-host.example"}
    end

    test "a redirect to http is refused even on the same host" do
      test_pid = self()

      Req.Test.stub(Downloader, fn conn ->
        send(test_pid, {:requested, conn.scheme})
        redirect(conn, "http://cdn.example.com/app.tar.gz")
      end)

      {:error, [%{action: :download}]} =
        assert Downloader.download(:url, %{path: "https://cdn.example.com/app.tar.gz"})

      assert_received {:requested, :https}
      refute_received {:requested, :http}
    end

    test "a redirect to the same host is followed, absolute or relative" do
      tarball = :crypto.strong_rand_bytes(16)

      Req.Test.stub(Downloader, fn conn ->
        case conn.request_path do
          "/app.tar.gz" -> redirect(conn, "/files/app.tar.gz")
          "/files/app.tar.gz" -> redirect(conn, "https://CDN.Example.com/final.tar.gz")
          "/final.tar.gz" -> binary_response(conn, tarball)
        end
      end)

      {:ok, body} =
        assert Downloader.download(:url, %{path: "https://cdn.example.com/app.tar.gz"})

      assert body == tarball
    end

    test "a redirect to a host of :url_hosts is followed" do
      tarball = :crypto.strong_rand_bytes(16)
      Application.put_env(:mishka_installer, :allowlist, url_hosts: ["files.example.org"])

      Req.Test.stub(Downloader, fn conn ->
        case conn.host do
          "cdn.example.com" -> redirect(conn, "https://files.example.org/app.tar.gz")
          "files.example.org" -> binary_response(conn, tarball)
        end
      end)

      {:ok, body} =
        assert Downloader.download(:url, %{path: "https://cdn.example.com/app.tar.gz"})

      assert body == tarball
    end

    test "a GitHub release asset may redirect to GitHub's release CDN" do
      tarball = :crypto.strong_rand_bytes(16)

      Req.Test.stub(Downloader, fn conn ->
        case conn.host do
          "github.com" ->
            redirect(conn, "https://release-assets.githubusercontent.com/asset?sig=abc")

          "release-assets.githubusercontent.com" ->
            binary_response(conn, tarball)
        end
      end)

      {:ok, body} =
        assert Downloader.download(:url, %{
                 path: "https://github.com/owner/repo/releases/download/0.1.0/app.tar.gz"
               })

      assert body == tarball
    end

    test "the GitHub release CDN is not allowed for a URL that is not on GitHub" do
      test_pid = self()

      Req.Test.stub(Downloader, fn conn ->
        send(test_pid, {:requested, conn.host})
        redirect(conn, "https://release-assets.githubusercontent.com/asset")
      end)

      {:error, [%{action: :download}]} =
        assert Downloader.download(:url, %{path: "https://cdn.example.com/app.tar.gz"})

      refute_received {:requested, "release-assets.githubusercontent.com"}
    end

    test "a GitHub latest-release install follows the asset redirect to the CDN" do
      tarball = :crypto.strong_rand_bytes(16)

      Req.Test.stub(Downloader, fn conn ->
        case conn.host do
          "api.github.com" ->
            Req.Test.json(conn, %{
              "assets" => [
                %{
                  "name" => "app.tar.gz",
                  "browser_download_url" =>
                    "https://github.com/owner/repo/releases/download/0.1.0/app.tar.gz"
                }
              ]
            })

          "github.com" ->
            redirect(conn, "https://release-assets.githubusercontent.com/asset")

          "release-assets.githubusercontent.com" ->
            binary_response(conn, tarball)
        end
      end)

      {:ok, body} = assert Downloader.download(:github_latest_release, %{path: "owner/repo"})
      assert body == tarball
    end

    test "three redirects are followed and a fourth is refused" do
      tarball = :crypto.strong_rand_bytes(16)

      Req.Test.stub(Downloader, fn conn ->
        case conn.request_path do
          "/hop/" <> n when n in ["0", "1", "2"] ->
            redirect(conn, "/hop/#{String.to_integer(n) + 1}")

          "/hop/3" ->
            binary_response(conn, tarball)

          "/loop/" <> n ->
            redirect(conn, "/loop/#{String.to_integer(n) + 1}")
        end
      end)

      {:ok, body} = assert Downloader.download(:url, %{path: "https://cdn.example.com/hop/0"})
      assert body == tarball

      {:error, [%{action: :download}]} =
        assert Downloader.download(:url, %{path: "https://cdn.example.com/loop/0"})
    end

    test "a redirect without a Location header is an error" do
      Req.Test.stub(Downloader, fn conn -> Plug.Conn.send_resp(conn, 302, "") end)

      {:error, [%{action: :download}]} =
        assert Downloader.download(:url, %{path: "https://cdn.example.com/app.tar.gz"})
    end
  end

  defp redirect(conn, location, status \\ 302) do
    conn
    |> Plug.Conn.put_resp_header("location", location)
    |> Plug.Conn.send_resp(status, "")
  end

  defp binary_response(conn, tarball) do
    conn
    |> Plug.Conn.put_resp_content_type("application/gzip", nil)
    |> Plug.Conn.send_resp(200, tarball)
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
