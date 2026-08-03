#!/usr/bin/env bash
# Production start/restart proof for mishka_installer.
#
# Builds a `mix release` of a host app that depends on mishka_installer, installs a pre-built `ebin`
# onto a temp "volume" (extensions dir + Mnesia disc dir), disables a plugin and halts the VM with no
# clean shutdown, then COLD-RESTARTS the OS process and asserts both the installed app and the
# operator's disable survived — the production boot path, plus the durability of a status write.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HERE/mishka_prod_test"

# Build artifacts live in a stable temp dir (NOT under the parent repo's test/ tree). mix.exs reads
# the same env var, so the release lands where REL points.
export MISHKA_FIXTURE_ARTIFACTS="${MISHKA_FIXTURE_ARTIFACTS:-${TMPDIR:-/tmp}/mishka_prod_test_artifacts}"
REL="$MISHKA_FIXTURE_ARTIFACTS/_build/prod/rel/mishka_prod_test/bin/mishka_prod_test"

# Pin the node to `localhost` so `bin/app rpc` reaches it on hosts whose short hostname resolves to
# something else (wildcard DNS, VPN); the default `-sname <app>` is resolved by the OS.
export RELEASE_DISTRIBUTION=sname
export RELEASE_NODE=mishka_prod_test@localhost

VOL="$(mktemp -d "${TMPDIR:-/tmp}/mishka_prod_vol.XXXXXX")"
export MISHKA_DATA_DIR="$VOL"
mkdir -p "$VOL/extensions" "$VOL/mnesia"

cleanup() { "$REL" stop >/dev/null 2>&1 || true; rm -rf "$VOL"; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "== pre-stage the artifact on the volume =="
elixir "$HERE/build_demo.exs" "$VOL/extensions/demo_plugin-0.1.0" demo_plugin 0.1.0 DemoPlugin

echo "== build the release (MIX_ENV=prod) =="
( cd "$APP_DIR" && MIX_ENV=prod mix deps.get && MIX_ENV=prod mix release --overwrite ) >/dev/null

wait_up() {
  for _ in $(seq 1 60); do
    "$REL" rpc "IO.puts(:up)" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

wait_active() {
  local s=""
  for _ in $(seq 1 60); do
    s="$("$REL" rpc 'MishkaProdTest.Demo.status_line()' 2>/dev/null | tr -d '\r')"
    echo "$s" | grep -q "started?=true record?=true hello=world" && { echo "$s"; return 0; }
    sleep 1
  done
  echo "$s"; return 1
}

wait_plugin() {
  local s=""
  for _ in $(seq 1 60); do
    s="$("$REL" rpc 'MishkaProdTest.Demo.plugin_line()' 2>/dev/null | tr -d '\r')"
    echo "$s" | grep -qE "status=(started|restarted|stopped)" && { echo "$s"; return 0; }
    sleep 1
  done
  echo "$s"; return 1
}

echo "== boot 1: install =="
"$REL" daemon
wait_up || fail "node 1 did not come up"
"$REL" rpc 'MishkaProdTest.Demo.install_cli()' | grep -q INSTALL_OK || fail "install failed"
S1="$(wait_active)" || fail "app not active after install: $S1"
echo "boot1: $S1"

echo "== boot 1: disable a plugin and halt the VM in the same breath (no clean shutdown) =="
P1="$(wait_plugin)" || fail "plugin never registered: $P1"
echo "$P1" | grep -q "status=started" || fail "plugin did not start: $P1"
OS_PID="$("$REL" pid)"
"$REL" rpc 'MishkaProdTest.Demo.disable_and_halt()' >/dev/null 2>&1 || true
sleep 2
kill -9 "$OS_PID" >/dev/null 2>&1 || true
sleep 2

echo "== boot 2: COLD restart after the unclean halt, no install =="
"$REL" daemon
wait_up || fail "node 2 did not come up"
S2="$(wait_active)" || fail "replay failed after restart: $S2"
echo "boot2: $S2"
P2="$(wait_plugin)" || fail "plugin record lost after restart: $P2"
echo "boot2: $P2"
echo "$P2" | grep -q "status=stopped" || fail "the disable did not survive the restart: $P2"
ID1="$(echo "$P1" | sed -n 's/.*id=\([^ ]*\).*/\1/p')"
ID2="$(echo "$P2" | sed -n 's/.*id=\([^ ]*\).*/\1/p')"
[ "$ID1" = "$ID2" ] || fail "the plugin was re-registered as a new row: $ID1 -> $ID2"
"$REL" stop

echo "PASS: install replay and an operator's disable both survived an unclean restart"
