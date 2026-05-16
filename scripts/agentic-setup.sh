#!/usr/bin/env bash
# agentic-setup.sh — Idempotent bootstrap (packages: core | interactive).
#
# Usage:
#   ./scripts/agentic-setup.sh --vault /abs/vault [--package core|interactive]
#   ./scripts/agentic-setup.sh --print-plan --vault /abs/vault ...
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/hardware.sh
source "$REPO_ROOT/scripts/lib/hardware.sh"
# shellcheck source=lib/packages.sh
source "$REPO_ROOT/scripts/lib/packages.sh"

DAEMON_DIR="$REPO_ROOT/gzmo-daemon"
ENV_FILE="$DAEMON_DIR/.env"

vault_path=""
package="core"
dropzone_dir=""
ollama_url="http://localhost:11434"
ollama_model=""
with_systemd=0
with_pi=0
skip_pi=0
with_api=0
force_env=0
print_plan=0
plugins=""

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  sed -n '1,35p' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) shift; vault_path="${1:-}" ;;
    --package) shift; package="${1:-core}" ;;
    --ollama-url) shift; ollama_url="${1:-}" ;;
    --ollama-model) shift; ollama_model="${1:-}" ;;
    --dropzone-dir) shift; dropzone_dir="${1:-}" ;;
    --no-desktop-dropzone) dropzone_dir="${dropzone_dir:-}" ;;
    --with-systemd) with_systemd=1 ;;
    --with-pi) with_pi=1; skip_pi=0 ;;
    --skip-pi) skip_pi=1 ;;
    --with-api) with_api=1 ;;
    --force-env) force_env=1 ;;
    --plugins) shift; plugins="${1:-}" ;;
    --print-plan) print_plan=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
  shift || true
done

[[ -n "$vault_path" ]] || die "--vault is required"
[[ "$vault_path" == /* ]] || die "VAULT_PATH must be absolute"
package="$(gzmo_normalize_package "$package")"

if [[ -z "$dropzone_dir" ]]; then
  dropzone_dir="$(default_desktop_dropzone_dir)"
fi
[[ "$dropzone_dir" == /* ]] || die "GZMO_DROPZONE_DIR must be absolute"

if [[ -z "$ollama_model" ]]; then
  ollama_model="$(hardware_recommended_chat_model)"
fi

mkdir -p "$dropzone_dir"/{_processed,_failed,files,_tmp}

plan_text() {
  cat <<EOF
agentic-setup plan:
  vault:        $vault_path
  package:      $package
  dropzone:     $dropzone_dir
  ollama_url:   $ollama_url
  ollama_model: $ollama_model
  systemd:      $with_systemd
  pi:           $with_pi  skip_pi=$skip_pi
  api:          $with_api
  plugins:      ${plugins:-"(none)"}
  force_env:    $force_env
EOF
}

plan_text
if (( print_plan == 1 )); then
  exit 0
fi

echo "agentic-setup: repo=$REPO_ROOT" >&2
mkdir -p \
  "$vault_path/GZMO/Inbox" \
  "$vault_path/GZMO/Subtasks" \
  "$vault_path/GZMO/Thought_Cabinet" \
  "$vault_path/GZMO/Quarantine" \
  "$vault_path/GZMO/Reasoning_Traces" \
  "$vault_path/wiki" \
  "$vault_path/wiki/incoming"

if command -v ollama >/dev/null 2>&1; then
  hardware_eval
  echo "agentic-setup: hardware tier=$HW_TIER model=$HW_CHAT_MODEL" >&2
  ollama_model="$(pull_chat_model_for_tier 2>/dev/null)" || ollama_model="$HW_CHAT_MODEL"
  pull_embed_model >/dev/null || true
fi

write_env_file() {
  local token=""
  if (( with_api == 1 )); then
    token="$(openssl rand -hex 32 2>/dev/null || echo change-me-set-GZMO_API_TOKEN)"
  fi
  gzmo_write_installer_env "$ENV_FILE" "$package" "$vault_path" "$ollama_url" "$ollama_model" "$dropzone_dir" "$with_api" "$token" "$plugins"
}

if [[ ! -f "$ENV_FILE" ]] || (( force_env == 1 )); then
  echo "agentic-setup: writing $ENV_FILE" >&2
  write_env_file
else
  echo "agentic-setup: keeping $ENV_FILE (use --force-env to replace)" >&2
fi

if command -v bun >/dev/null 2>&1 || [[ -x "${HOME:-}/.bun/bin/bun" ]]; then
  (cd "$DAEMON_DIR" && bun install)
fi

if (( with_systemd == 1 )); then
  (cd "$REPO_ROOT" && ./install_service.sh) || true
fi

if (( with_pi == 1 && skip_pi == 0 )); then
  install_pi_coding_stack "$REPO_ROOT" || true
elif (( skip_pi == 1 )); then
  echo "agentic-setup: Pi install skipped (--skip-pi)" >&2
fi

export GZMO_ENV_FILE="$ENV_FILE"
if [[ -x "$REPO_ROOT/scripts/local-self-check.sh" ]]; then
  "$REPO_ROOT/scripts/local-self-check.sh" --write-vault || true
fi

echo "agentic-setup: done — export GZMO_ENV_FILE=\"$ENV_FILE\"" >&2
