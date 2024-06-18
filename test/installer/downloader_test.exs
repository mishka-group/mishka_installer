defmodule MishkaInstallerTest.Installer.DownloaderTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Installer.Downloader

  setup do
    Application.put_env(:mishka_installer, :downloader_req_options, plug: {Req.Test, Downloader})
  end

  test "Moc hex test" do
    Req.Test.stub(Downloader, fn conn ->
      Req.Test.json(conn, %{"latest_stable_version" => "0.0.4"})
    end)

    {:ok, %{"latest_stable_version" => "0.0.4"}} =
      assert Downloader.get_mix(:hex, %{app: "mishka_installer", tag: "0.0.4"})

    {:ok, %{"latest_stable_version" => "0.0.4"}} =
      assert Downloader.get_mix(:hex, %{app: "mishka_installer"})
  end

  test "Github release/tag test" do
    Req.Test.stub(Downloader, fn conn ->
      Req.Test.text(conn, "mix file")
    end)

    {:ok, "mix file"} =
      assert Downloader.get_mix(:github_release, %{path: "mishka_installer", release: "0.0.4"})

    {:ok, "mix file"} =
      assert Downloader.get_mix(:github_tag, %{path: "mishka_installer", tag: "0.0.4"})
  end

  test "Github test" do
    url = "https://raw.githubusercontent.com/mishka-group/mishka_developer_tools/master/mix.exs"

    Req.Test.stub(Downloader, fn conn ->
      Req.Test.json(conn, %{"download_url" => url})
    end)

    {:ok, %{"download_url" => ^url}} =
      assert Downloader.get_mix(:github, %{path: "mishka-group/mishka_developer_tools"})
  end

  test "Github latest release test" do
    Req.Test.stub(Downloader, fn conn ->
      Req.Test.json(conn, %{"tag_name" => "0.0.4"})
    end)

    {:ok, %{"tag_name" => "0.0.4"}} =
      assert Downloader.get_mix(:github_latest_release, %{
               path: "mishka-group/mishka_developer_tools"
             })
  end

  test "Github latest tag test" do
    Req.Test.stub(Downloader, fn conn ->
      Req.Test.json(conn, [%{"name" => "0.0.4"}])
    end)

    {:ok, [%{"name" => "0.0.4"}]} =
      assert Downloader.get_mix(:github_latest_tag, %{path: "mishka-group/mishka_developer_tools"})
  end

  test "URL test" do
    url = "https://raw.githubusercontent.com/mishka-group/mishka_developer_tools/master/mix.exs"

    Req.Test.stub(Downloader, fn conn ->
      Req.Test.text(conn, url)
    end)

    {:ok, ^url} = assert Downloader.get_mix(:url, %{path: url})
  end
end
