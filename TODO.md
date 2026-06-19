# MishkaInstaller — TODO / Known Problems

> Working notes. Severity: 🔴 critical · 🟠 high · 🟡 medium · ⚪ low.

## ✅ Done — installer reworked to ebin-only (this change set)

The runtime-**compile** installer (`mix deps.get/deps.compile/compile` via `System.cmd`/`Port`) was
**deleted** (it can't run in a release) and replaced with a **pre-built `ebin` installer** that works
in dev and in a `mix release`:

- **Deleted dead code:** `LibraryHandler.do_compile`, `command_execution` (`:cmd`/`:port`/`:mix`) +
  Port loop + Agent state, `move`/`write_downloaded_lib`, `move_and_replace_build_files` (the
  `_build` copy), `mix_exist`, `Installer.Collect`. Source-compile download removed.
- **Kept + repurposed:** download of a **pre-built artifact** (`Downloader` → `:url` /
  `:github_tag` / `:github_latest_release`, `raw: true` so Req returns the on-wire `tar.gz`),
  ebin-aware `extract`, `prepend_compiled_apps`, `application_ensure`, `read_app`, `unload`.
- **Install flow:** validate name → resolve package (local `:path` or download+extract) → check
  `ebin`/`.app` → version guard → `Code.prepend_path` → `Application.load` + `ensure_all_started`
  → persist record. **Rollback** on partial failure.
- **Safety:** app-name regex before any `String.to_atom` (atom-table), path-traversal guard
  (`Path.expand`), version guard (`:gt` only), `:temporary` start type (a bad plugin can't take the
  node down), idempotent `application_ensure` (`{:already_loaded}` → `:ok`).
- **Restart persistence:** ebin lives in the **writable extensions dir** (configurable via
  `:extensions_path`, not `_build`); the `Installer` record (`disc_copies`) survives; `CompileHandler`
  replays prepend+load on Mnesia `:synchronized`, now **fault-isolated** per app (one bad extension
  no longer freezes the system).
- **Tests:** mix-free fixtures; covers local + download install, **restart persistence**,
  path-traversal, version guard, rollback, extract. Full suite: **70 tests, 0 failures**.

Remaining for production hardening (not yet done): artifact **checksum/signature** verification,
recording + checking the building **OTP/Elixir version**, **NIF/native** gating, a real
**release-mode** (embedded) smoke test.

---

> The items below are the original audit; the installer-specific ones above are now resolved.

---

## 0. 🔴 BIGGEST PROBLEM — the runtime installer cannot work in production

**The approach (download source → `mix` compile → load) is unworkable in a `mix release`.**

```
Installer.install/1
  ① download    ✅ prod-ok (HTTP via Req)
  ② extract     ✅ prod-ok (:erl_tar)
  ③ mix compile ❌ BREAKS — needs mix + Hex + project build context
  ④ load app    ✅ only if compiled beams already exist
```

Why it fails on a release node:

- `mix` executable is **not shipped** in a release → `System.cmd("mix", ...)` (`lib/installer/library_handler.ex:295`) and `System.find_executable("mix")` (`:port`, `library_handler.ex:329`) find nothing.
- **Hex is not shipped** → `mix deps.get` cannot resolve/fetch deps.
- **No build context** — no project `mix.exs` / deps tree / proper `_build` to compile against.
- Net: `LibraryHandler.do_compile/1` (`library_handler.ex:68`: `deps.get → deps.compile → compile`) cannot execute in prod.

What *does* work at runtime: loading **already-compiled** BEAM artifacts via
`Code.prepend_path` + `Application.ensure_all_started` (`library_handler.ex:107,421`).

Confirmed by our own docs: README "installer… may not work in the Elixir release";
dev-only hints (disable `live_reload`, set `reloadable_apps`).

- [ ] **Decision:** delete the runtime-compile installer for the CMS use case
      (branch `delete-installer-prove-for-cms`) and keep/prove the Event engine, **OR**
- [ ] Re-scope the installer to *load pre-compiled artifacts only* (no `mix` at runtime), **OR**
- [ ] Document it explicitly as a **dev/build-time-only** tool and gate it out of releases.

---

## 1. Correctness bugs

- [ ] 🟠 `lib/event/hook.ex:441` — `handle_info(:re_event)` computes `new_state` but returns `{:noreply, state}`; the recomputed status is silently discarded.
- [ ] 🟠 `lib/event/event.ex:427,517` — `stop/unregister(:event)` with `queue: false` calls `ModuleStateCompiler.purge_create([], event)`, wiping **all** surviving plugins; diverges from the `queue: true` path which recomputes the correct set.
- [ ] 🟠 `lib/installer/installer.ex:228` — `uninstall/1` is `@spec uninstall(atom())` but the body uses `app.app` (expects a struct/map) and passes a String into `Application.stop`. Only `uninstall/2` is correct/exercised.
- [ ] 🟡 `lib/event/event.ex:486` — `unregister(:name, ...)` deletes the DB row *then* `GenServer.stop/2`; if the process isn't alive the `with` fails after deletion → DB/process inconsistency.
- [ ] 🟡 `lib/event/event.ex:293` — `restart(:name, ...)` writes `depends_status` (possibly `:held`) *before* the `plugin_status` check → partial write on the error path.
- [ ] 🟡 `lib/installer/installer.ex:629` — `install_and_compile_steps/1` does destructive, non-transactional steps (stop + `rm_rf!` old sub-app before the new copy is confirmed); a later `application_ensure` failure leaves the host with the old app gone and the new one not started (no rollback).
- [ ] 🟡 `lib/installer/library_handler.ex:561` — `compare_version_with_installed_app` allows only `:gt`, so re-installing the **same** version to repair a broken install is silently skipped (looks successful, empty `prepend_paths`).

## 2. Config / wiring mismatches

- [ ] 🟡 `lib/mnesia_repo.ex:47` — config read under key `Mishka.MnesiaRepo`, but the module is `MishkaInstaller.MnesiaRepo` → user config under the real module name is silently ignored.
- [ ] 🟡 `mix.exs` — `test_coverage` ignore lists `MishkaInstaller.Installer.PortHandler`, which **does not exist** (Port logic is inline in `LibraryHandler.command_execution(:port, ...)`).
- [ ] 🟡 `mix.exs` — `package.files` lists `Changelog.md` but the repo file is `CHANGELOG.md` (case mismatch) → risks omission from the Hex package / broken hexdocs changelog link.
- [ ] 🟡 `lib/mishka_installer.ex:259` — `__information__/0` can `String.to_atom(nil)` and raise when `MIX_ENV` / `:project_env` / compile-time `@project_env` are all unset (Mix-less release); it runs inside compile-time `if` macros.

## 3. Error handling / logging

- [ ] 🟡 `lib/installer/compile_handler.ex:147` and `:114` — interpolate a list/struct into `"Source: #{errors}"` → `Protocol.UndefinedError` (String.Chars) **exactly when logging a real failure**, masking it.
- [ ] ⚪ `lib/event/module_state_compiler.ex` — generated `call/2` has a blanket `rescue` returning original state; a single non-conforming plugin `call/1` return silently nullifies the whole event chain.
- [ ] ⚪ `lib/event/event.ex` — `stop/unregister/restart(:event)` all emit error `action: :restart_event` (copy-paste); `group_events/1` logs `"deleting"` on a read error.

## 4. Security posture (installer)

- [ ] 🔴 Arbitrary remote-code-exec surface: downloads from hex/github/**any URL** and runs the package's `mix.exs` + build scripts. No checksum/registry-signature validation (`hex_core` is test-only), no TLS pinning, no sandbox, no allowlist. The configurable `:proxy` is merged into **every** request.
- [ ] 🟠 Path handling: only `:extracted` is guarded by `allowed_extract_path/1`; app/version/branch/path are interpolated into FS paths + URLs after only `String.trim` (no `../` sanitizing). Trust pushed entirely onto the caller.
- [ ] 🟡 Global-state hazards: installs mutate VM-global cwd (`File.cd!`) and a single named Agent for `:port` output → installs **must** be serialized; heavy `String.to_atom(data.app)` is an atom-table-exhaustion path.
- [ ] ⚪ Mitigation today is **documentation only** (moduledocs "high access level, admin-only"; `SECURITY.md` = one email). The "not user-facing" assumption is load-bearing and unenforced by code.

## 5. Test coverage gaps

- [ ] 🟡 No test calls a compiled event module's `call/2` with real data → data transformation through the chain, `:halt`, and `:private`/`:return` merging are documented but **never behaviorally tested**.
- [ ] 🟡 `test/installer/installer_test.exs` "FunctionsTest" block is **empty** — `install`/`uninstall`/`async_install` orchestration has no direct coverage.
- [ ] 🟡 Dependency *resolution* direction (dep becomes active → dependent auto-starts) untested; only the `:held` blocking direction is asserted.
- [ ] ⚪ `test/installer/library_handler_test.exs:85` references a missing fixture (`mishka_developer_tools-0.1.8.tar.gz`); the test passes for the **wrong reason** (extract errors on the nonexistent file).
- [ ] ⚪ `RegisterOTPSender` and several `Bulk.*` fixtures are defined but never referenced by name in tests.

## 6. Meta / docs drift

- [ ] ⚪ `telemetry` is a declared dep with **zero call sites**.
- [ ] ⚪ Version refs scattered: README badge `0.1.0`, deps snippet `~> 0.1.3`, CHANGELOG stops at `0.1.1`, `mix.exs` `@version 0.1.5`.
- [ ] ⚪ `.iex.exs` hardcodes an absolute macOS path (`/Users/shahryar/...`) and a localhost:2080 proxy — author-machine-specific, not portable.
- [ ] ⚪ CI covers only Elixir 1.17.1 / OTP 27.0, though `mix.exs` allows `~> 1.17` (incl. 1.18); history mentions an "elixir 1.18 problem" fix not exercised by CI.

## 7. In-flight branch

- [ ] Branch `delete-installer-prove-for-cms` is 1 commit ahead of `master` ("Update deps"): only deps bumps (`req 0.5.17→0.6.1`, `guarded_struct →0.1.0-beta.8`) + mechanical `derive:`→`derives:` rename across `Event`/`Installer` + one test assertion. **The installer deletion implied by the branch name is NOT done yet** (see #0).
