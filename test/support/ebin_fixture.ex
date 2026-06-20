defmodule MishkaInstallerTest.Support.EbinFixture do
  @moduledoc false
  # Builds a tiny, **pre-built** OTP application on disk WITHOUT `mix`:
  # a compiled `.beam` (via `Code.compile_string/1`) plus a hand-written `ebin/<app>.app` resource.
  # This is exactly the shape the ebin-only installer consumes, so the installer can be tested
  # end-to-end (including restart replay) with no compiler, no Port and no network.

  @doc """
  Writes `<pkg_dir>/ebin/{<app>.app, <Module>.beam}` and returns `{app, module, ebin_dir}`.
  """
  @spec build_fake_app(Path.t(), atom(), String.t(), term()) :: {atom(), module(), Path.t()}
  def build_fake_app(pkg_dir, app, version, result \\ :world) do
    ebin = Path.join(pkg_dir, "ebin")
    File.mkdir_p!(ebin)
    module = Module.concat([Macro.camelize("#{app}")])

    [{^module, bin}] =
      Code.compile_string("""
      defmodule #{inspect(module)} do
        use Application
        def start(_type, _args), do: Supervisor.start_link([], strategy: :one_for_one)
        def hello(), do: #{inspect(result)}
      end
      """)

    File.write!(Path.join(ebin, "#{module}.beam"), bin)

    app_term =
      {:application, app,
       [
         description: ~c"#{app}",
         vsn: ~c"#{version}",
         modules: [module],
         registered: [],
         applications: [:kernel, :stdlib, :elixir],
         mod: {module, []}
       ]}

    File.write!(
      Path.join(ebin, "#{app}.app"),
      :erlang.iolist_to_binary(:io_lib.format(~c"~p.~n", [app_term]))
    )

    {app, module, ebin}
  end

  @doc """
  Builds a fake app and returns a gzipped tarball (binary) whose top level is `ebin/...`,
  alongside `{app, module}`. Used to exercise the download + extract path.
  """
  @spec tar_fake_app(atom(), String.t(), term()) :: {binary(), atom(), module()}
  def tar_fake_app(app, version, result \\ :world) do
    uniq = System.unique_integer([:positive])
    src = Path.join(System.tmp_dir!(), "ebin-fixture-#{app}-#{uniq}")
    {^app, module, ebin} = build_fake_app(src, app, version, result)
    tar = Path.join(System.tmp_dir!(), "#{app}-#{version}-#{uniq}.tar.gz")

    :ok =
      :erl_tar.create(String.to_charlist(tar), [{~c"ebin", String.to_charlist(ebin)}], [
        :compressed
      ])

    body = File.read!(tar)
    File.rm_rf!(src)
    File.rm!(tar)
    {body, app, module}
  end
end
