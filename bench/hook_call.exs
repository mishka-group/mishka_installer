# Measures the hot paths of mishka_installer: `Hook.call/3` over compiled chains of 0, 1 and 5
# plugins, and the plugin registry reads of `MishkaInstaller.Event.Event`.
#
#     MIX_ENV=test mix run bench/hook_call.exs
#
# Each line is the median of 7 rounds, in nanoseconds per operation. The `parallel` lines run the
# same read from 16 processes at once and report the wall time of all of them, per operation.
# It lives outside `lib/`, so it is not part of the package.
Logger.configure(level: :warning)

defmodule Bench.Pass do
  def call(state), do: {:reply, state}
end

for n <- 1..5 do
  defmodule Module.concat(Bench, "Plugin#{n}") do
    def call(state), do: {:reply, state}
  end
end

defmodule Bench.Meta do
  def call(state, _meta), do: {:reply, state}
end

defmodule Bench do
  @rounds 7

  def run(label, fun, n \\ 200_000) do
    loop(fun, div(n, 10))
    times = for _ <- 1..@rounds, do: elem(:timer.tc(fn -> loop(fun, n) end), 0)
    report(label, median(times) * 1000 / n)
  end

  def parallel(label, fun, procs \\ 16, n \\ 20_000) do
    loop(fun, div(n, 10))

    times =
      for _ <- 1..@rounds do
        {micros, _} =
          :timer.tc(fn ->
            1..procs
            |> Enum.map(fn _ -> Task.async(fn -> loop(fun, n) end) end)
            |> Task.await_many(:infinity)
          end)

        micros
      end

    report(label, median(times) * 1000 / (procs * n))
  end

  defp median(times), do: times |> Enum.sort() |> Enum.at(div(@rounds, 2))

  defp report(label, ns),
    do:
      IO.puts(
        String.pad_trailing(label, 52) <> :erlang.float_to_binary(ns, decimals: 1) <> " ns/op"
      )

  defp loop(_fun, 0), do: :ok

  defp loop(fun, n) do
    fun.()
    loop(fun, n - 1)
  end
end

alias MishkaInstaller.Event.{Event, Hook, ModuleStateCompiler}

build = fn names, event ->
  for name <- names do
    {:ok, plugin} = Event.builder(%{name: name, event: event, extension: :mishka_installer})
    plugin
  end
end

five = for n <- 1..5, do: Module.concat(Bench, "Plugin#{n}")
:ok = ModuleStateCompiler.create([], "bench:zero")
:ok = ModuleStateCompiler.create(build.([Bench.Pass], "bench:one"), "bench:one")
:ok = ModuleStateCompiler.create(build.(five, "bench:five"), "bench:five")
:ok = ModuleStateCompiler.create(build.(five ++ [Bench.Meta], "bench:meta"), "bench:meta")

payload = %{site_id: "site", user: %{id: 1}, body: "hello"}
meta = %{actor: :bench}

IO.puts("Hook.call/3 (#{System.otp_release()} / Elixir #{System.version()})")
Bench.run("  not compiled", fn -> Hook.call("bench:missing", payload) end)
Bench.run("  0 plugins", fn -> Hook.call("bench:zero", payload) end)
Bench.run("  1 plugin", fn -> Hook.call("bench:one", payload) end)
Bench.run("  5 plugins", fn -> Hook.call("bench:five", payload) end)

Bench.run("  5 plugins, cannot_run: and meta:", fn ->
  Hook.call("bench:five", payload, cannot_run: :cannot_run, meta: meta)
end)

Bench.run("  6 plugins, one takes meta", fn -> Hook.call("bench:meta", payload, meta: meta) end)
Bench.parallel("  5 plugins, parallel", fn -> Hook.call("bench:five", payload) end)

tmp = Path.join(System.tmp_dir!(), "mishka-bench-#{System.unique_integer([:positive])}")

Application.put_env(:mishka_installer, MishkaInstaller.MnesiaRepo,
  mnesia_dir: tmp,
  essential: [Event]
)

{:ok, _repo} = MishkaInstaller.MnesiaRepo.start_link()

for {name, priority} <- Enum.with_index(five, 1) do
  {:ok, _} =
    Event.write(%{
      name: name,
      event: "bench:registry",
      extension: :mishka_installer,
      status: :started,
      priority: priority
    })
end

IO.puts("\nRegistry reads (5 plugins stored)")
Bench.run("  Event.get(:event, event)", fn -> Event.get(:event, "bench:registry") end, 50_000)
Bench.run("  Event.get(:name, plugin)", fn -> Event.get(:name, Bench.Plugin3) end, 50_000)
Bench.run("  Event.get()", fn -> Event.get() end, 50_000)
Bench.parallel("  Event.get(:name, plugin), parallel", fn -> Event.get(:name, Bench.Plugin3) end)

:mnesia.stop()
File.rm_rf!(tmp)
