defmodule MishkaInstallerTest.Installer.DownloaderTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Installer.Downloader

  setup do
    Application.put_env(:mishka_installer, :downloader_req_options, plug: {Req.Test, Downloader})

    {:ok, %{tarball: tarball}} =
      :hex_tarball.create(
        %{
          "name" => "foo",
          "version" => "1.0.0"
        },
        [
          {~c"mix.exs",
           """
           defmodule Foo.MixProject do
             use Mix.Project
             def project do
               [app: :foo, version: "1.0.0"]
             end
           end
           """}
        ]
      )

    %{tarball: tarball}
  end

  describe "Download Mock Test ===>" do
    test "Downloade hex with version with creating tarball", %{tarball: tarball} do
      tar_expect_200(tarball)

      {:ok, _body} = Downloader.download(:hex, %{app: "mishka_installer", tag: "0.0.4"})

      tar_expect_400(tarball)

      {:error, _error} =
        assert Downloader.download(:hex, %{app: "mishka_installer", tag: "0.0.4"})
    end

    test "Downloade hex with version", %{tarball: tarball} do
      tar_expect_200(tarball)

      {:ok, _body} = Downloader.download(:hex, %{app: "mishka_installer", tag: "0.0.4"})

      tar_expect_400(tarball)

      {:error, _error} =
        assert Downloader.download(:hex, %{app: "mishka_installer", tag: "0.0.4"})
    end

    test "Downloade github branch", %{tarball: tarball} do
      tar_stub_200(tarball)

      {:ok, _body} =
        assert Downloader.download(:github, %{
                 path: "mishka_installer",
                 branch: {"master", git: true}
               })

      {:ok, _body} =
        assert Downloader.download(:github, %{path: "mishka_installer", branch: "master"})

      tar_expect_400(tarball)

      {:error, _error} =
        assert Downloader.download(:github, %{
                 path: "mishka_installer",
                 branch: {"master", git: true}
               })

      tar_expect_400(tarball)

      {:error, _error} =
        assert Downloader.download(:github, %{path: "mishka_installer", branch: "master"})
    end

    test "Downloade github release/tag", %{tarball: tarball} do
      tar_stub_200(tarball)

      {:ok, _body} =
        assert Downloader.download(:github, %{path: "mishka_installer", release: "0.0.4"})

      {:ok, _body} =
        assert Downloader.download(:github, %{path: "mishka_installer", tag: "0.0.4"})

      tar_expect_400(tarball)

      {:error, _error} =
        assert Downloader.download(:github, %{path: "mishka_installer", release: "0.0.4"})

      tar_expect_400(tarball)

      {:error, _error} =
        assert Downloader.download(:github, %{path: "mishka_installer", tag: "0.0.4"})
    end

    test "Download hex without version", %{tarball: tarball} do
      Req.Test.expect(Downloader, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"latest_stable_version" => "0.0.4"}))
      end)

      tar_expect_200(tarball)

      {:ok, _body} =
        assert Downloader.download(:hex, %{app: "mishka_installer"})

      tar_expect_400(tarball)

      {:error, _error} = assert Downloader.download(:hex, %{app: "mishka_installer"})
    end
  end

  describe "Get mix Mock Test ===>" do
    test "Mock hex" do
      Req.Test.stub(Downloader, fn conn ->
        Req.Test.json(conn, %{"latest_stable_version" => "0.0.4"})
      end)

      {:ok, %{"latest_stable_version" => "0.0.4"}} =
        assert Downloader.get_mix(:hex, %{app: "mishka_installer", tag: "0.0.4"})

      {:ok, %{"latest_stable_version" => "0.0.4"}} =
        assert Downloader.get_mix(:hex, %{app: "mishka_installer"})

      Req.Test.stub(Downloader, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"tag_name" => "0.0.4"})
      end)

      {:error, _error} =
        assert Downloader.get_mix(:hex, %{app: "mishka_installer", tag: "0.0.4"})

      {:error, _error} =
        assert Downloader.get_mix(:hex, %{app: "mishka_installer"})
    end

    test "Github release/tag" do
      Req.Test.stub(Downloader, fn conn ->
        Req.Test.text(conn, "mix file")
      end)

      {:ok, "mix file"} =
        assert Downloader.get_mix(:github_release, %{path: "mishka_installer", release: "0.0.4"})

      {:ok, "mix file"} =
        assert Downloader.get_mix(:github_tag, %{path: "mishka_installer", tag: "0.0.4"})

      Req.Test.stub(Downloader, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.text("mix file")
      end)

      {:error, _error} =
        assert Downloader.get_mix(:github_release, %{path: "mishka_installer", release: "0.0.4"})

      {:error, _error} =
        assert Downloader.get_mix(:github_tag, %{path: "mishka_installer", tag: "0.0.4"})
    end

    test "Github" do
      url = "https://raw.githubusercontent.com/mishka-group/mishka_developer_tools/master/mix.exs"

      Req.Test.stub(Downloader, fn conn ->
        Req.Test.json(conn, %{"download_url" => url})
      end)

      {:ok, %{"download_url" => ^url}} =
        assert Downloader.get_mix(:github, %{path: "mishka-group/mishka_developer_tools"})

      Req.Test.stub(Downloader, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"tag_name" => "0.0.4"})
      end)

      {:error, _error} =
        assert Downloader.get_mix(:github, %{path: "mishka-group/mishka_developer_tools"})
    end

    test "Github latest release" do
      Req.Test.stub(Downloader, fn conn ->
        Req.Test.json(conn, %{"tag_name" => "0.0.4"})
      end)

      {:ok, %{"tag_name" => "0.0.4"}} =
        assert Downloader.get_mix(:github_latest_release, %{
                 path: "mishka-group/mishka_developer_tools"
               })

      Req.Test.stub(Downloader, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"tag_name" => "0.0.4"})
      end)

      {:error, _error} =
        assert Downloader.get_mix(:github_latest_release, %{
                 path: "mishka-group/mishka_developer_tools"
               })

      Req.Test.expect(Downloader, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"tag_name" => "0.0.4"}))
      end)

      Req.Test.expect(Downloader, &Plug.Conn.send_resp(&1, 200, "body string"))

      {:ok, "body string"} =
        assert Downloader.get_mix(:github_latest_release, %{
                 path: "mishka-group/mishka_developer_tools"
               })
    end

    test "Github latest tag" do
      Req.Test.stub(Downloader, fn conn ->
        Req.Test.json(conn, [%{"name" => "0.0.4"}])
      end)

      {:ok, [%{"name" => "0.0.4"}]} =
        assert Downloader.get_mix(:github_latest_tag, %{
                 path: "mishka-group/mishka_developer_tools"
               })

      Req.Test.stub(Downloader, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json([%{"name" => "0.0.4"}])
      end)

      {:error, _} =
        assert Downloader.get_mix(:github_latest_tag, %{
                 path: "mishka-group/mishka_developer_tools"
               })
    end

    test "URL" do
      url = "https://raw.githubusercontent.com/mishka-group/mishka_developer_tools/master/mix.exs"

      Req.Test.stub(Downloader, fn conn ->
        Req.Test.text(conn, url)
      end)

      {:ok, ^url} = assert Downloader.get_mix(:url, %{path: url})

      Req.Test.stub(Downloader, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.text(url)
      end)

      {:error, _error} = assert Downloader.get_mix(:url, %{path: url})
    end
  end

  defp tar_expect_200(tarball) do
    Req.Test.expect(Downloader, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/octet-stream", nil)
      |> Plug.Conn.send_resp(200, tarball)
    end)
  end

  defp tar_stub_200(tarball) do
    Req.Test.stub(Downloader, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/octet-stream", nil)
      |> Plug.Conn.send_resp(200, tarball)
    end)
  end

  defp tar_expect_400(tarball) do
    Req.Test.expect(Downloader, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/octet-stream", nil)
      |> Plug.Conn.send_resp(400, tarball)
    end)
  end
end
