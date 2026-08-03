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
