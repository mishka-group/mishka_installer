---
name: elixir-otp-anti-pattern-audit
description: Audit this Elixir/OTP project for the official Elixir & Erlang anti-patterns — GenServer bottlenecks, hot-path try/rescue, runtime module introspection in loops, dynamic atoms. Use when reviewing performance/structure, before merging, or when adding hot-path code.
---

# Elixir/OTP anti-pattern audit

Classify every suspect by **call path**, then judge — severity follows the path, not the construct:

- **hot** = per-request dispatch (`Hook.call/3`) or a tight loop → fix it.
- **warm** = periodic/background loop (timers, polls) → fix if it scales with N.
- **cold** = boot / compile / admin / diagnostic → usually fine as-is.

A `try/rescue`, `apply/3`, or `function_exported?` on a **cold** path is fine; the same on a **hot** path is the bug. **Always trace callers before judging.**

This file is **extensible** — check the boxes as you refactor, and add new items as more are found.

## Open items in THIS project (audit 2026-06)

- [x] **WARM — plugin status poll hit Mnesia every ~1s per plugin.** `lib/event/hook.ex` `plugin_status_poll/2` now uses `Event.dirty_get(:name, module)` (a non-transactional dirty index read) instead of `Event.get` (a txn) — same result, no lock/commit overhead. (Further option if it ever matters: push via the `:re_event` broadcast and drop the poll entirely.)
- [x] **HOT (low) — per-dispatch string→atom.** `ModuleStateCompiler.module_event_name/1` now **memoizes** the event-string→module atom in `:persistent_term` (write-once, lock-free reads), so `Hook.call/3` no longer reruns `String.to_atom`+trim/replace/regex/camelize each dispatch. (The `function_exported?(module, :call, 2)` guard stays — it's the cheap, intentional "ghost event returns data unchanged" safety; `String.to_existing_atom` hardening is moot now that the name is cached.)
- [ ] **HOT (low) — generated `call/2` per-dispatch `rescue` + `apply/3`.** `lib/event/module_state_compiler.ex` `create/3` emits an outer `rescue` and `perform/2` does `apply(h.name, :call, [state])` per plugin. **Accepted** (one frame; dynamic dispatch ≈ ns). _Optional: unroll to static `Mod.call(state)` AST at compile time since plugin names are already baked in._
- [x] **WARM (by design) — `EventHandler` serializes compiles.** Intentional mutual-exclusion around `:code.purge`/recompile/cluster-broadcast; not a bug. Monitor `Process.info(pid, :message_queue_len)`; shard by event hash only if churn ever bites.
- [x] **COLD — no action:** `rescue_initialize?` (dead code), health-probe `rescue`+`catch` (intentional, time-boxed in a `spawn_monitor`), compile-path `Code.ensure_loaded?` in `EventHandler.perform`.

## Reusable checklist

### GenServer / process bottlenecks
- [ ] **Code organization by process** — a GenServer doing pure logic/lookups with no real concurrency need. Grep `GenServer.call\|handle_call`. Fix: plain functions; keep the process only for genuine runtime concerns.
- [ ] **Process instead of ETS for read-heavy shared state** — a server mostly answering "value for key K". Fix: ETS (`read_concurrency: true`) or `:persistent_term`; keep the process only to serialize writes.
- [ ] **Blocking/CPU-bound work in `handle_call`** — stalls every queued caller. Fix: `GenServer.reply` from a spawned worker, or move state to ETS.

### Hot-path try/rescue & exceptions
- [ ] **try/rescue/catch as control flow** on hot paths/loops. Grep `rescue\|catch \|try do`, confirm each is cold. Fix: pattern-match expected shapes; return `{:ok,_}`/`{:error,_}` on the fast path.
- [ ] **Reifying stack traces on the hot path** — `__STACKTRACE__` per request/loop. Fix: capture only where a real crash is logged.

### Runtime introspection in loops
- [ ] **`function_exported?` / `Code.ensure_loaded?` / `apply/3` on hot/warm paths.** Grep `function_exported?\|Code.ensure_loaded\|apply(`. Fix: cache the boolean/module ref at compile/register time (`:persistent_term`); prefer a direct static call or compile-time AST.
- [ ] **Periodic poll doing DB/introspection on a timer.** Grep `send_after\|send_interval`. Fix: push on change via broadcast/PubSub; cache in ETS/`:persistent_term`.

### Dynamic atoms
- [ ] **Dynamic atom creation** — `String.to_atom`/`*_to_atom` on runtime input. Grep `to_atom`. Fix: `*_to_existing_atom`, or an allow-list map; convert once, not per call.
- [ ] **Dynamic apply with built atoms** — `apply(String.to_atom(...), ...)`. Fix: dispatch via a map keyed by the string to `{Module, Fun}`.

### Untracked / compile-time deps
- [ ] **Untracked compile-time deps** — `Module.concat`/`:"Elixir.#{name}"` building names dynamically. Fix: explicit module names, or generate AST in a macro. (Intentional runtime DB-driven modules are NOT this anti-pattern.)
- [ ] **Macro compile-time deps** — DSL macros referencing module args in a module body → recompilation cascades. Fix: expand inside a generated function (`Macro.expand_literals/2`).

### Non-assertive access
- [ ] **Non-assertive map access** — `map[:key]` for required keys (returns `nil`). Fix: `map.key` / match in the head; reserve `[:key]` for optional keys.
- [ ] **Non-assertive pattern matching** — `Enum.at` without bounds, catch-all `_`, tolerating wrong arities. Fix: assert shape (`[k, v] = String.split(...)`), match all expected `case` clauses.

### Design / control flow
- [ ] **Unrelated multi-clause function/module** — `@doc` says "if called like X… if like Y…". Fix: split into named functions.
- [ ] **`with`…`else` flattening distinct errors** — an `else _ -> ...` collapsing different failures. Grep `with `, inspect `else`. Fix: match each error shape, or let the tagged error propagate unchanged.
- [ ] **Folklore micro-optimization** — contortions "because BEAM is slow", blanket tail-recursion, NIF-first. Fix: don't optimize on myth; profile (`fprof`/`eprof`). NIFs are a last resort.

## References

- Elixir: [code](https://hexdocs.pm/elixir/code-anti-patterns.html) · [design](https://hexdocs.pm/elixir/design-anti-patterns.html) · [process](https://hexdocs.pm/elixir/process-anti-patterns.html) · [macro](https://hexdocs.pm/elixir/macro-anti-patterns.html) anti-patterns
- Erlang Efficiency Guide: [processes](https://www.erlang.org/doc/system/eff_guide_processes.html) · [common caveats](https://www.erlang.org/doc/system/commoncaveats.html) · [seven myths](https://www.erlang.org/doc/system/myths.html)
