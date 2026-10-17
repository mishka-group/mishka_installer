# Changelog for MishkaInstaller 0.1.14

### Fixed:

- A `version:` that is not a semantic version no longer crashes `Installer.install/1`. With an app
  of that name already loaded, a version such as `"1.0"` raised `Version.InvalidVersionError` from
  the comparison with the running app; with none loaded, it was installed as it was. Both versions
  are now parsed with `Version.parse/1`, and a bad one is answered with
  `{:error, [%{field: :version, action: :compare_version_with_installed_app, ...}]}`, or
  `field: :app` when the loaded app's own `vsn` is not one
- Upgrading an installed app updates its record instead of writing a second one. `update_or_write/2`
  looked the record up by id with the app's name, found nothing, and wrote a new record with the
  same app every time, so `get(:app, ...)` could answer either one and `uninstall/1` removed only one

### Changed:

- **(BREAKING CHANGE)** The installer's `version` field is validated as a semantic version
  (`MAJOR.MINOR.PATCH`, with optional pre-release and build). `builder/1`, `write/1`, `install/1`
  and `async_install/1` refuse anything else with
  `{:error, [%{field: :version, action: :semver, ...}]}` before anything is installed

# Changelog for MishkaInstaller 0.1.13

### Fixed:

- A plugin removed or renamed in a newer version of its extension no longer takes its event down.
  Its registration outlived its module in Mnesia, so the event compiled to a stub that ran none of
  the plugins that were still there, until the record was unregistered by hand. On boot, once the
  run-time extensions are loaded and before the events start, every plugin whose extension's
  application is loaded and no longer has its module is now unregistered, with a warning, so
  whatever depended on it is held as `unregister/3` holds it
- A plugin whose application is not loaded is left as it was: its event still runs none of its
  plugins, since that extension may still be on its way in — and compiling an event to that stub now
  logs an error naming the plugins it is waiting for, once per compile, where before it was silent
- An event whose state is not a list, a map, `{:ok, _}` or `{:error, _}` — a LiveView callback's
  `{:noreply, socket}` or `{:ok, socket, layout: ...}`, a binary — now comes back as its plugins left
  it. The compiled chain had no clause for it: every call raised inside it, logged
  `plugin pipeline raised`, and answered the state it was handed, so what the plugins returned was
  thrown away — and an event left with no plugins logged that error on every call

### Changed:

- **(BREAKING CHANGE)** An event that cannot run — one of its plugins is started but not loaded —
  now answers `Hook.call/3` and `Hook.call!/3` with the state they were given, or with the answer
  named in their new `cannot_run:` option, instead of
  `{:error, [%{action: :call, field: :event, plugins: [...]}]}`. Every caller had to tell that error
  apart from its plugins' answer before it could go on without them; a caller whose decision must
  refuse when its plugins cannot run, such as a security gate, now names its refusal:
  `Hook.call("auth:gate:check", gate, cannot_run: %{gate | allowed?: false})`. An event whose
  plugins all run ignores the option

### Features:

- `cannot_run:` option on `MishkaInstaller.Event.Hook.call/3` and `MishkaInstaller.Event.Hook.call!/3`
- `MishkaInstaller.Event.Event.unregister_gone/1`
- `[:mishka_installer, :event, :unregistered_gone]` telemetry for each plugin unregistered this way,
  with `:plugin`, `:event` and `:extension`

# Changelog for MishkaInstaller 0.1.12

### Fixed:

- Two advisories in the dependency tree, both already fixed upstream and both reached only by
  updating: `hpax` 1.0.3 -> 1.0.4 (EEF-CVE-2026-58226, HIGH — unauthenticated denial of service via
  unbounded HPACK integer decoding) and `html_sanitize_ex` 1.5.1 -> 1.5.5 (EEF-CVE-2026-68750 and
  EEF-CVE-2026-68749, both HIGH, plus three lower ones)

### Changed:

- **(BREAKING CHANGE)** `req` is now `~> 0.7`, up from `~> 0.6.1`. The old requirement was not just
  this library's business: hex resolves a single `req` for the whole dependency tree, so no
  application depending on this one could raise `req` in any of its own `mix.exs` files —
  resolution failed outright rather than choosing a side. Nothing here uses what 0.7 changed
  (`current_request_steps`, and the `run_finch` / `put_plug` / `run_plug` steps that became adapter
  modules); the whole Req surface is `Req.request!/1` and a `%Req.Response{}` match
- Dependency floors raised to what is actually resolved and tested: `phoenix_pubsub ~> 2.3`,
  `plug ~> 1.20`, `guarded_struct ~> 0.1.1`
- `read_app/2`'s test no longer pins the version of the library it reads, so a dependency bump stops
  failing a test that is really about parsing an `.app` file

# Changelog for MishkaInstaller 0.1.11

### Features:

- Add `MishkaInstaller.Event.Event.enable/2` (and `enable/0` on a Hook plugin) as the explicit
  inverse of `stop/3`, and the **only** transition out of `:stopped`
- Disabling, unregistering or holding a plugin now holds everything that depends on it,
  transitively and across events, and switching it back on releases them again — no plugin
  anywhere keeps a list of its dependents (`Event.sync_dependents/2`, `Event.dependents/1`)
- `register/3` is an upsert on the plugin name: the fields declared in code (`:priority`,
  `:extra`, `:depends`) are re-applied on every boot, the runtime ones (`:id`, `:status`,
  `:inserted_at`) are preserved

### Fixed:

- A status change is now durable: lifecycle writes commit with
  `MishkaInstaller.Helper.MnesiaAssistant.Transaction.durable_transaction/1` (sync commit + log
  flush), so a plugin an operator disabled stays disabled after an unclean shutdown. Previously
  the write only reached the disk on Mnesia's periodic dump (three minutes by default) and a node
  that died in between came back with the plugin re-enabled
- The generated `is_changed?/1` compares the incoming chain with the compiled one by equality
  instead of testing for a subset, so a plugin **leaving** an event (stopped, held, unregistered)
  rebuilds the chain immediately instead of running until the next boot
- `restart/3` checks every condition before it writes: a failed restart no longer leaves a status
  behind that the compiled chain disagrees with, and it can no longer re-enable a stopped plugin
- `stop/3` accepts a `:held` plugin, so a plugin blocked by a missing dependency can still be
  switched off by an operator
- Dependency resolution no longer promotes a plugin without looking at its own status, so a
  disabled plugin is never resurrected by one of its dependencies starting
- A plugin held at boot because a dependency on **another** event had not started yet is now
  released when that dependency starts, instead of staying dark until the next restart

### Breaking:

- `restart/3` returns an error for a `:stopped` plugin; use `enable/2` to switch it back on
- Registering an already-registered plugin updates the row instead of inserting a second one
- Statuses of dependent plugins now change on their own when a dependency is stopped or started

# Changelog for MishkaInstaller 0.1.10

### Fixed:

- Log an error when a Hook's boot registration fails (previously only a `:register_error`
  broadcast that nothing listens to by default — e.g. a plugin whose `priority` breaks the
  0..100 contract was rejected invisibly and sat dormant with no record).

# Changelog for MishkaInstaller 0.1.9

### Fixed:

- Self-heal plugins stuck in `:registered` limbo: a Hook whose stored record says `:registered`
  (its very first `start` never completed — e.g. an interrupted boot between the two Mnesia
  writes) is now started again at boot instead of silently staying dormant forever. `:stopped`
  and `:held` records are still respected — the operator's switch survives restarts.

# Changelog for MishkaInstaller 0.1.8

### Features:

- Add optional :meta arg passing read-only context to `call/2` plugins

# Changelog for MishkaInstaller 0.1.6

### Features:

- Rework the Installer to load **pre-built `ebin`** artifacts at runtime (`:path`, `:url`, `:github_tag`, `:github_latest_release`) with no `mix`/source compilation — release-safe [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Add a `Req`-based `Downloader` for `:url`/`:github_tag`/`:github_latest_release` artifact downloads [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Add an install allow/deny policy via `config :mishka_installer, :allowlist` (`url_hosts`, `github_repos`, `protected_apps`) [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Add optional SHA-256 `checksum:` verification for downloaded artifacts [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Replay installed apps on boot via `Installer.CompileHandler` — re-load and start from disk + Mnesia, working in a release's embedded code-loading mode [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Add a plugin health-check system: optional `health_check/0` plus `Hook.plugin_health/2`, `event_health/2`, and `health/1` [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Add the optional `on_dependency_error/1` Hook callback for reacting to registration/dependency errors [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Add `Hook.profile/2` to measure each plugin's run time in a compiled event chain [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Add dynamic Mnesia cluster membership to `MnesiaRepo` (auto/seed/join, `disc_copies`, node up/down handling) [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Add a volume-friendly, configurable `:extensions_path` and Mnesia dir, a Production deployment guide, and a real `mix release` start/restart test [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Add `lib/helper` utilities (`Helper.Extra`, `Helper.UUID`) and `QueueAssistant` [#102](https://github.com/mishka-group/mishka_installer/pull/102)

### Refactors:

- Unroll the plugin call chain at compile time in `ModuleStateCompiler` (direct dispatch, `{:reply, state}` continue / `{:reply, :halt, state}` halt) and memoize the event→module mapping in `:persistent_term` for the hot `Hook.call/3` path [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- **Breaking** — move the Mnesia helpers under the `Helper` namespace: `MishkaInstaller.MnesiaAssistant.*` → `MishkaInstaller.Helper.MnesiaAssistant.*` (now in `lib/helper/`) [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- **Breaking** — make the installer allowlist **fail-closed**: an empty/absent `url_hosts`/`github_repos` now blocks remote installs (local `:path` installs are unaffected) [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Remove the legacy runtime-compilation path (`System.cmd`/`Port` running `mix deps.get`/`compile`) and `installer/collect.ex` [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Slim the `Hook` macro to thin delegators (logic centralized in `Event.Hook`) and explicitly load installed app modules for release (embedded) mode [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Expand the test suite with real/dynamic tests (real Hook GenServers, real Mnesia, `Req.Test`) and raise coverage [#102](https://github.com/mishka-group/mishka_installer/pull/102)

### Bugs:

- Fix dependency auto-start: lifecycle broadcasts carried empty data, so a `:held` plugin never auto-started when the dependency it waited on activated [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Fix infinite recursion in `Helper.MnesiaAssistant.Error.error_description/2` on an unknown aborted-tuple reason [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Fix path traversal: reject an `app`/`version` whose resolved package path escapes the extensions directory before any `File.rm_rf!`/`rename`/extract (install and uninstall) [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Fix tar-slip: reject archive members with absolute or `..` paths before extraction [#102](https://github.com/mishka-group/mishka_installer/pull/102)
- Fix `@impl`/deprecation/codegen warnings (declare `on_dependency_error/1`, `module.initialize?()` parens, generated `:halt` clause) [#102](https://github.com/mishka-group/mishka_installer/pull/102)


# Changelog for MishkaInstaller 0.1.1

### Global

- [x] Add `guarded_struct` dep
- [x] Update all deps and test for Elixir 1.17.2

### Improvement:

- [x] Add `callbacks` and `behaviour` to Hook macro [Link](https://github.com/mishka-group/mishka_installer/commit/faee57ab069cf0b5dd09e6f93c35cf8978ad9e2d)


# Changelog for MishkaInstaller 0.1.0

> Kindly ensure that the MishkaInstaller Library is updated as quickly as feasible. This version includes rewriting whole project. It should be noted we do not support previous versions.

You will see that this version of the project has undergone a total overhaul, and the strategy that was taken to it has been radically altered.

Because of this, it is not possible to write down the details, and each area has its own document that you are able to study thoroughly.

- Based on: https://github.com/mishka-group/mishka_installer/pull/99
