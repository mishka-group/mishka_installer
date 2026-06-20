<div align="center">

# 🧩 MishkaInstaller

**A runtime plugin / event engine and pre-built library installer for Elixir.** ✨

[![Hex.pm](https://img.shields.io/hexpm/v/mishka_installer.svg?style=flat-square)](https://hex.pm/packages/mishka_installer)
[![Hex Downloads](https://img.shields.io/hexpm/dt/mishka_installer.svg?style=flat-square)](https://hex.pm/packages/mishka_installer)
[![CI](https://img.shields.io/github/actions/workflow/status/mishka-group/mishka_installer/ci.yml?style=flat-square)](https://github.com/mishka-group/mishka_installer/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/mishka_installer.svg?style=flat-square)](https://github.com/mishka-group/mishka_installer/blob/master/LICENSE)
[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-mishka--group-ea4aaa?style=flat-square&logo=github)](https://github.com/sponsors/mishka-group)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_a_Coffee-mishkagroup-ffdd00?style=flat-square&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/mishkagroup)

</div>

---

> [!WARNING]
> **🔧 Low maintenance.** The author currently only responds to pull requests. Don't use `master`; the current release line is `0.1.6`.

---

## 💭 Why?

Build apps whose features are **activated as plugins at runtime** — registration, SMS, social login — **without touching the core source**. Each feature becomes an **event**; anyone can attach plugins to it from outside your app.

---

## ✨ Features

- 🔌 **Events & Hooks** — register plugins for an event; they run in **priority + dependency** order.
- ⚡ **Fast dispatch** — each event compiles to a module, so `Hook.call/3` is a direct call: no GenServer, no DB on the read path.
- 🩺 **Health checks** — optional per-plugin `health_check/0`, inspected via `Hook.event_health/1`.
- 🌐 **Multi-node** — the Mnesia-backed store joins & replicates across a cluster automatically.
- 📦 **Runtime installer** — load **pre-built `ebin`** artifacts (local path, URL, or GitHub release). Works in a `mix release`.

---

## 🔌 Events & Hooks

Define a plugin for an event — it auto-registers and runs whenever the event is called:

```elixir
defmodule RegisterEmailSender do
  use MishkaInstaller.Event.Hook, event: "after_success_login"

  @impl true
  def call(entries), do: {:reply, entries}
end
```

```elixir
# tweak defaults
use MishkaInstaller.Event.Hook,
  event: "after_success_login",
  initial: %{depends: [SomeEvent], priority: 20}
```

Call every plugin registered for an event:

```elixir
alias MishkaInstaller.Event.Hook

Hook.call("after_success_login", params)
Hook.call("after_success_login", params, private: keep_this)  # extra data, untouched by plugins
Hook.call("after_success_login", params, return: true)        # return the original input
```

To start a plugin automatically, add its module to your supervision tree:

```elixir
children = [RegisterEmailSender, ...]
```

> [!NOTE]
> A plugin's `depends` always run **before** it (cycles are rejected at registration), and a plugin can return `{:reply, :halt, state}` to stop the rest of the chain. See `MishkaInstaller.Event.Hook`.

[![Run in Livebook](https://livebook.dev/badge/v1/pink.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fmishka-group%2Fmishka_installer%2Fblob%2Fmaster%2Fguidance%2Fevent%2Fhook.livemd)

---

## 📦 Installer

Load an **already-compiled `ebin`** at runtime — no source compilation, so it's release-safe:

```elixir
alias MishkaInstaller.Installer.Installer

Installer.install(%{app: "demo", version: "0.1.0", type: :path,                  path: "/ext/demo-0.1.0"})
Installer.install(%{app: "demo", version: "0.1.0", type: :url,                   path: "https://.../demo-ebin.tar.gz"})
Installer.install(%{app: "demo", version: "0.1.0", type: :github_tag,            path: "owner/repo", tag: "0.1.0"})
Installer.install(%{app: "demo", version: "0.1.0", type: :github_latest_release, path: "owner/repo"})

Installer.uninstall(%{app: "demo", version: "0.1.0"})
```

> [!NOTE]
> Remote installs (`:url`/`:github_*`) are **fail-closed**: they require the source host/repo in `config :mishka_installer, :allowlist, url_hosts:/github_repos:`. Optional `checksum:` (sha256) pins the artifact; `:protected_apps` guards apps from being overwritten/removed. See `MishkaInstaller.Installer.Installer`.

---

## 🏭 Production deployment

An installed library is a pre-built `ebin` on disk plus a Mnesia record; on every boot it is replayed (put back on the code path and started). So **both** the `ebin`s and the Mnesia data must live on a **persistent (mounted) volume** — otherwise installs do not survive a restart/redeploy. Point both at your volume (here `/data`):

```elixir
# config/runtime.exs — /data is your mounted volume
config :mishka_installer,
  project_path: "/data",
  extensions_path: "/data/extensions"

config :mishka_installer, MishkaInstaller.MnesiaRepo,
  mnesia_dir: "/data/mnesia",
  essential: [MishkaInstaller.Event.Event, MishkaInstaller.Installer.Installer]
```

`:extensions_path` is where `ebin`s are written; `mnesia_dir` is where the records live; `:essential` are the tables created on boot (the plugin and install stores — keep both). Just depend on `:mishka_installer`; its supervision tree starts automatically outside `:test`.

> A real release restart proof lives in `test/integration/production_release/` — run it with `mix test --only production_release`.

---

## 🚀 Installation

```elixir
def deps do
  [{:mishka_installer, "~> 0.1.6"}]
end
```

Docs: [hexdocs.pm/mishka_installer](https://hexdocs.pm/mishka_installer)

---

## 💖 Funding & sponsorship

MishkaInstaller is open-source software developed by [Mishka Group](https://github.com/mishka-group). If your team or company benefits from it, please consider supporting continued development:

<div align="center">

[![GitHub Sponsors](https://img.shields.io/badge/GitHub_Sponsors-mishka--group-ea4aaa?style=for-the-badge&logo=github&logoColor=white)](https://github.com/sponsors/mishka-group)
&nbsp;&nbsp;&nbsp;
[![Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_a_Coffee-mishkagroup-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/mishkagroup)

**☕ Donate / sponsor:**
[github.com/sponsors/mishka-group](https://github.com/sponsors/mishka-group) · [buymeacoffee.com/mishkagroup](https://www.buymeacoffee.com/mishkagroup)

</div>

Thank you. 💚

---

## 📜 License

Apache License 2.0 — see [`LICENSE`](LICENSE).

Copyright © Mishka Group and contributors.
