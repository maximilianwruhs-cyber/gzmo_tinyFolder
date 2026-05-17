#!/usr/bin/env bash
# gzmo-daemon-start.sh — Idempotent background start (cron @reboot, manual, boot-stack fallback).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_DIR="$REPO_ROOT/gzmo-daemon"
ENV_FILE="${GZMO_ENV_FILE:-$DAEMON_DIR/.env}"
WAIT_SCRIPT="$REPO_ROOT/scripts/wait-for-ollama.sh"
LOG_DIR=""
PID_FILE=""

die() { echo "gzmo-start: ERROR: $*" >&2; exit 1; }

[[ -f "$ENV_FILE" ]] || die "missing $ENV_FILE — run ./scripts/setup-local.sh --vault /abs/vault --with-api"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

export GZMO_ENV_FILE="$ENV_FILE"
export PATH="${HOME}/.bun/bin:${HOME}/.local/bin:${PATH:-/usr/bin:/bin}"

command -v bun >/dev/null 2>&1 || die "bun not found (install: https://bun.sh)"

vault_path="${VAULT_PATH:-}"
[[ -n "$vault_path" && "$vault_path" == /* ]] || die "VAULT_PATH must be absolute in $ENV_FILE"

LOG_DIR="${vault_path}/logs"
PID_FILE="${LOG_DIR}/daemon.pid"
mkdir -p "$LOG_DIR"

api_port="${GZMO_API_PORT:-12700}"
api_token="${GZMO_API_TOKEN:-}"
health_url="http://127.0.0.1:${api_port}/api/v1/health"

health_ok() {
  local hdr=()
  [[ -n "$api_token" ]] && hdr=(-H "Authorization: Bearer ${api_token}")
  curl -sf "${hdr[@]}" "$health_url" >/dev/null 2>&1
}

if health_ok; then
  echo "gzmo-start: already healthy at ${health_url}" >&2
  exit 0
fi

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "gzmo-start: stopping stale pid ${old_pid}" >&2
    kill "$old_pid" 2>/dev/null || true
    sleep 2
  fi
fi

pkill -f "${DAEMON_DIR}.*bun run summon" 2>/dev/null || true
pkill -f "${DAEMON_DIR}.*index.ts" 2>/dev/null || true
sleep 1

if [[ -x "$WAIT_SCRIPT" ]]; then
  GZMO_SYSTEMD_WAIT_FOR_OLLAMA="${GZMO_SYSTEMD_WAIT_FOR_OLLAMA:-1}" "$WAIT_SCRIPT" || \
    echo "gzmo-start: WARN: Ollama not ready — starting daemon anyway" >&2
fi

cd "$DAEMON_DIR"
nohup bun run summon >>"${LOG_DIR}/daemon.log" 2>&1 &
echo $! >"$PID_FILE"
echo "gzmo-start: started pid $(cat "$PID_FILE"), log ${LOG_DIR}/daemon.log" >&2

for _ in $(seq 1 30); do
  if health_ok; then
    echo "gzmo-start: healthy" >&2
    exit 0
  fi
  sleep 1
done

echo "gzmo-start: daemon started but health check failed — see ${LOG_DIR}/daemon.log" >&2
exit 1
