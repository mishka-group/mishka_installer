# 🧩 Mishka Installer

> A runtime **plugin / event engine** and **pre-built library installer** for Elixir.

[![MishkaInstaller CI](https://github.com/mishka-group/mishka_installer/actions/workflows/ci.yml/badge.svg)](https://github.com/mishka-group/mishka_installer/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/badge/hex-0.1.5-blue.svg)](https://hex.pm/packages/mishka_installer) [![GitHub license](https://img.shields.io/badge/apache-2.0-green.svg)](https://raw.githubusercontent.com/mishka-group/mishka_installer/master/LICENSE) ![GitHub issues](https://img.shields.io/github/issues/mishka-group/mishka_installer)

<div align="center">
  <pre style="display: inline-block; text-align: left;">
    💖 Hey there! If you like my work, please <b><a href="https://github.com/sponsors/mishka-group">support me financially!</a></b> 💖
  </pre>
</div>

<br />

<p align="center">
  <a href="https://www.buymeacoffee.com/mishkagroup">
    <img src="https://github.com/user-attachments/assets/f4d4df7e-dcc4-4d1a-80e1-59c4d99725ab" alt="Support Mishka by Buy Me a Coffee" />
  </a>
</p>

> ⚠️ **Low maintenance** — the author currently only responds to pull requests.
> Don't use `master`; the current release line is `0.1.5`.

---

## Why?

Build apps whose features are **activated as plugins at runtime** — registration, SMS, social login — **without touching the core source**. Each feature becomes an **event**; anyone can attach plugins to it from outside your app.

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

> A plugin's `depends` always run **before** it (cycles are rejected at registration). See `MishkaInstaller.Event.Hook`.

[![Run in Livebook](https://livebook.dev/badge/v1/pink.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fmishka-group%2Fmishka_installer%2Fblob%2Fmaster%2Fguidance%2Fevent%2Fhook.livemd)

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

Optional `checksum:` (sha256) verification and an allow/deny policy (`config :mishka_installer, :allowlist, ...`). See `MishkaInstaller.Installer.Installer`.

## 📥 Install

```elixir
def deps do
  [{:mishka_installer, "~> 0.1.5"}]
end
```

Docs: [hexdocs.pm/mishka_installer](https://hexdocs.pm/mishka_installer)

---

## 💚 Donate

Support this project via the **[Sponsor](https://github.com/sponsors/mishka-group)** button on GitHub. All our projects are **open-source** and **free** — community contributions keep them growing.
