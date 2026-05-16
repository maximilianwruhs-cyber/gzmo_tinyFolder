#!/usr/bin/env bash
#
# setup-local.sh — Canonical install: hardware-sized model + vault + .env
#
# Usage:
#   ./scripts/setup-local.sh --vault /abs/vault
#   ./scripts/setup-local.sh --vault /abs/vault --package interactive
#   ./scripts/setup-local.sh --vault /abs/vault --plugins dreams,pulse --force-env
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/hardware.sh
source "$REPO_ROOT/scripts/lib/hardware.sh"
# shellcheck source=lib/packages.sh
source "$REPO_ROOT/scripts/lib/packages.sh"

vault_path=""
package="core"
dropzone_dir=""
ollama_model=""
with_systemd=0
with_api=0
force_env=0
print_plan=0
plugins=""

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
setup-local.sh — write gzmo-daemon/.env + vault scaffold

Required:
  --vault /absolute/path/to/vault

Options:
  --package core|interactive     (default: core)
  --plugins id1,id2              optional plugins (docs/PLUGINS.md)
  --dropzone-dir /abs/path       default: ~/Schreibtisch or ~/Desktop/GZMO-Dropzone
  --ollama-model TAG             default: from hardware-report.sh
  --with-systemd                 install user systemd unit
  --with-api                     loopback HTTP API + token
  --force-env                    overwrite gzmo-daemon/.env
  --print-plan
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) shift; vault_path="${1:-}" ;;
    --package) shift; package="${1:-core}" ;;
    --dropzone-dir) shift; dropzone_dir="${1:-}" ;;
    --ollama-model) shift; ollama_model="${1:-}" ;;
    --with-systemd) with_systemd=1 ;;
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
[[ "$dropzone_dir" == /* ]] || die "dropzone must be absolute"

if [[ -z "$ollama_model" ]]; then
  ollama_model="$(hardware_recommended_chat_model)"
fi

cat <<EOF
setup-local plan:
  vault:        $vault_path
  package:      $package
  plugins:      ${plugins:-"(none)"}
  dropzone:     $dropzone_dir
  ollama_model: $ollama_model
  systemd:      $(( with_systemd ))
  api:          $(( with_api ))
EOF

if (( print_plan == 1 )); then
  exit 0
fi

args=(
  --vault "$vault_path"
  --package "$package"
  --dropzone-dir "$dropzone_dir"
  --ollama-model "$ollama_model"
  --skip-pi
)
[[ -n "$plugins" ]] && args+=(--plugins "$plugins")
(( force_env == 1 )) && args+=(--force-env)
(( with_systemd == 1 )) && args+=(--with-systemd)
(( with_api == 1 )) && args+=(--with-api)

exec "$REPO_ROOT/scripts/agentic-setup.sh" "${args[@]}"
