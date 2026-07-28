#!/usr/bin/env bash
# Dev/test Anthropic API key, stored ON THE BOX in the macOS Keychain — never in the repo, never in
# a plaintext dotfile, never pasted into a chat. Live-cloud testing (and, later, routine authoring)
# needs a real key; regenerating one every session is friction that also churns keys for no security
# gain, so it is stored once and read on demand.
#
# Why the Keychain rather than ~/.plenara/config.json or a .env: the key is encrypted at rest, it is
# not readable by a stray `cat` of the home directory, and it does not sit in a file that a sync
# provider or a backup might carry off the machine.
#
#   tool/devkey.sh set     # prompts (input hidden) and stores it — RUN THIS YOURSELF
#   tool/devkey.sh get     # prints the key (for `export ANTHROPIC_API_KEY=$(tool/devkey.sh get)`)
#   tool/devkey.sh check   # says whether a key is stored, WITHOUT printing it
#   tool/devkey.sh run …   # runs a command with ANTHROPIC_API_KEY set — the preferred use
#   tool/devkey.sh rm      # delete it
#
# Prefer `run`: it keeps the key out of shell history, out of the process list, and out of any log.
set -euo pipefail
SERVICE="plenara-anthropic-dev"
ACCOUNT="${USER}"

case "${1:-}" in
  set)
    # -w with no value makes `security` prompt on the tty with echo off.
    printf 'Paste the Anthropic API key (input hidden), then press return:\n' >&2
    read -r -s KEY
    [ -n "$KEY" ] || { echo "empty — nothing stored" >&2; exit 1; }
    security add-generic-password -U -s "$SERVICE" -a "$ACCOUNT" -w "$KEY"
    unset KEY
    echo "stored in the login keychain (service: $SERVICE)" >&2
    ;;
  get)
    security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w
    ;;
  check)
    if security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w >/dev/null 2>&1; then
      echo "a key IS stored (service: $SERVICE)"
    else
      echo "no key stored — run: tool/devkey.sh set"
      exit 1
    fi
    ;;
  run)
    shift
    [ $# -gt 0 ] || { echo "usage: tool/devkey.sh run <command …>" >&2; exit 1; }
    ANTHROPIC_API_KEY="$(security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w)" exec "$@"
    ;;
  rm)
    security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null
    echo "deleted" >&2
    ;;
  *)
    sed -n '2,17p' "$0"
    exit 1
    ;;
esac
