# Pre-builds a tiny real OTP app (a compiled .beam + ebin/<app>.app) on disk — the artifact the
# release installs. Run with full Elixir (has the compiler); the release never compiles at runtime.
# usage: elixir build_demo.exs <pkg_dir> <app> <version> <ModuleName>
[pkg, app_s, version, mod_s] = System.argv()
app = String.to_atom(app_s)
module = Module.concat([mod_s])
ebin = Path.join(pkg, "ebin")
File.rm_rf!(pkg)
File.mkdir_p!(ebin)

[{^module, bin}] =
  Code.compile_string("""
  defmodule #{inspect(module)} do
    use Application
    def start(_type, _args), do: Supervisor.start_link([], strategy: :one_for_one)
    def hello, do: :world
  end
  """)

File.write!(Path.join(ebin, "#{module}.beam"), bin)

app_term =
  {:application, app,
   [
     description: ~c"demo plugin",
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

IO.puts("built #{app} at #{ebin}")
