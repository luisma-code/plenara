#!/usr/bin/env bash
# Mirror the built-in capability defs (v0/data) into the app's bundled Flutter assets, so a SHIPPED
# binary can first-run on a machine with no repo. v0 is a pure-Dart package and can't declare Flutter
# assets, so the app carries a copy. The set here matches exactly what ensureSeeded() copies (NOT
# records/, which is user data). Run after changing v0/data; `--check` verifies the mirror is in sync
# (used by tool/precheck.sh so drift is a gate failure, never a silently-stale shipped app).
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT/v0/data"
DST="$ROOT/app/assets/seed"
SUBS="types skills templates automations reference"

do_sync() { # $1 = dest dir
  local d="$1"
  rm -rf "$d"; mkdir -p "$d"
  cp "$SRC/corpus.json" "$d/corpus.json"
  for s in $SUBS; do mkdir -p "$d/$s"; cp "$SRC/$s"/*.json "$d/$s/"; done
}

if [ "${1:-}" = "--check" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  do_sync "$tmp"
  if ! diff -r "$tmp" "$DST" >/dev/null 2>&1; then
    echo "!! app/assets/seed is OUT OF SYNC with v0/data — run: tool/sync_seed.sh" >&2
    exit 1
  fi
  echo "seed assets in sync with v0/data"
else
  do_sync "$DST"
  echo "synced $SRC -> $DST ($(find "$DST" -type f | wc -l | tr -d ' ') files)"
fi
