#!/usr/bin/env bash
# boot-stack.sh — One-shot: Ollama (if available) + GZMO daemon (systemd user or script fallback).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WAIT_SCRIPT="$REPO_ROOT/scripts/wait-for-ollama.sh"
START_SCRIPT="$REPO_ROOT/scripts/gzmo-daemon-start.sh"
ENV_FILE="${GZMO_ENV_FILE:-$REPO_ROOT/gzmo-daemon/.env}"

chmod +x "$WAIT_SCRIPT" "$START_SCRIPT" 2>/dev/null || true

start_ollama() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "gzmo-boot: systemctl not found; ensure Ollama is running (ollama serve)" >&2
    return 0
  fi
  local load
  load="$(systemctl show ollama.service --property=LoadState --value 2>/dev/null || true)"
  if [[ "$load" != "loaded" ]]; then
    echo "gzmo-boot: no ollama.service — start Ollama manually if needed" >&2
    return 0
  fi
  if systemctl is-active --quiet ollama 2>/dev/null; then
    echo "gzmo-boot: ollama.service already active" >&2
    return 0
  fi
  echo "gzmo-boot: starting ollama.service…" >&2
  systemctl start ollama 2>/dev/null || sudo systemctl start ollama 2>/dev/null || \
    echo "gzmo-boot: could not start ollama.service — try: ./scripts/start-ollama-optimized.sh" >&2
}

start_ollama

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

export GZMO_ENV_FILE="$ENV_FILE"
GZMO_SYSTEMD_WAIT_FOR_OLLAMA=1 "$WAIT_SCRIPT" || true

if command -v systemctl >/dev/null 2>&1 && systemctl --user show gzmo-daemon.service --property=LoadState --value 2>/dev/null | grep -q loaded; then
  if systemctl --user start gzmo-daemon 2>/dev/null; then
    echo "gzmo-boot: started via systemctl --user" >&2
    systemctl --user --no-pager status gzmo-daemon 2>/dev/null || true
    exit 0
  fi
  echo "gzmo-boot: systemctl --user unavailable — using gzmo-daemon-start.sh" >&2
fi

exec "$START_SCRIPT"
