#!/usr/bin/env bash
# audit-core-env.sh — Validate gzmo-daemon/.env against core package expectations.
#
# Usage:
#   ./scripts/audit-core-env.sh
#   ./scripts/audit-core-env.sh --env-file /path/to/.env
#   ./scripts/audit-core-env.sh --suggest
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${GZMO_ENV_FILE:-$REPO_ROOT/gzmo-daemon/.env}"
suggest=0
issues=0
warns=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) shift; ENV_FILE="${1:-}" ;;
    --suggest) suggest=1 ;;
    -h|--help) sed -n '1,10p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
  shift || true
done

fail() { echo "FAIL: $*" >&2; issues=$((issues + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }
pass() { echo "OK:   $*" >&2; }

get_env() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true
}

if (( suggest == 1 )); then
  cat <<'EOF'
# Suggested core .env block (merge with installer output)
GZMO_PROFILE=core
OLLAMA_URL=http://localhost:11434
GZMO_EMBED_MODEL=nomic-embed-text
GZMO_ENABLE_MODEL_ROUTING=off
GZMO_ENABLE_DROPZONE=on
GZMO_API_ENABLED=0
# GZMO_DROPZONE_DIR="/absolute/path/to/GZMO-Dropzone"
EOF
  exit 0
fi

[[ -f "$ENV_FILE" ]] || { fail "missing $ENV_FILE"; exit 1; }
echo "audit-core-env: $ENV_FILE" >&2

profile="$(get_env GZMO_PROFILE)"
case "$profile" in
  core|interactive) pass "GZMO_PROFILE=$profile" ;;
  "") warn "GZMO_PROFILE unset (daemon defaults to core)" ;;
  *) warn "GZMO_PROFILE=$profile (install packages: core | interactive only)" ;;
esac

vault="$(get_env VAULT_PATH)"
[[ -n "$vault" && "$vault" == /* ]] && pass "VAULT_PATH absolute" || fail "VAULT_PATH must be absolute"

drop="$(get_env GZMO_DROPZONE_DIR)"
[[ -n "$drop" && "$drop" == /* ]] && pass "GZMO_DROPZONE_DIR set" || warn "GZMO_DROPZONE_DIR unset (use desktop default at install)"

routing="$(get_env GZMO_ENABLE_MODEL_ROUTING)"
[[ "$routing" == "on" || "$routing" == "1" || "$routing" == "true" ]] && fail "GZMO_ENABLE_MODEL_ROUTING must be off for core package"

for bad in GZMO_FAST_MODEL GZMO_REASON_MODEL GZMO_JUDGE_MODEL OLLAMA_DRAFT_MODEL; do
  [[ -n "$(get_env "$bad")" ]] && fail "$bad is set (second chat model — remove)"
done

api="$(get_env GZMO_API_ENABLED)"
[[ "$api" == "1" || "$api" == "on" || "$api" == "true" ]] && warn "GZMO_API_ENABLED on (optional; default package keeps API off)"

model="$(get_env OLLAMA_MODEL)"
[[ -n "$model" ]] && pass "OLLAMA_MODEL=$model" || fail "OLLAMA_MODEL unset"

embed="$(get_env GZMO_EMBED_MODEL)"
[[ -z "$embed" || "$embed" == "nomic-embed-text" ]] && pass "embed model OK" || warn "GZMO_EMBED_MODEL=$embed (expected nomic-embed-text)"

if [[ "$profile" == "core" ]]; then
  for flag in GZMO_ENABLE_GAH GZMO_ENABLE_DSJ GZMO_ENABLE_TEACHBACK; do
  v="$(get_env "$flag")"
  [[ "$v" == "on" || "$v" == "1" ]] && warn "$flag=on with profile core (use interactive package if intentional)"
  done
fi

echo "audit-core-env: $issues fail(s), $warns warn(s)" >&2
(( issues == 0 )) || exit 1
