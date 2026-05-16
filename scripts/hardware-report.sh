#!/usr/bin/env bash
# hardware-report.sh — Machine spec + fit hint for Ollama chat model (run before setup).
#
# Usage:
#   ./scripts/hardware-report.sh
#   ./scripts/hardware-report.sh --json
#   ./scripts/hardware-report.sh --write-vault /abs/vault
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/hardware.sh
source "$REPO_ROOT/scripts/lib/hardware.sh"

json=0
write_vault=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) json=1 ;;
    --write-vault) shift; write_vault="${1:-}" ;;
    -h|--help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
  shift || true
done

hardware_eval

os_name="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}" || uname -s)"
cpu_model="$(lscpu 2>/dev/null | awk -F: '/Model name/{print $2; exit}' | sed 's/^[[:space:]]*//' || echo unknown)"
cpu_cores="$(nproc 2>/dev/null || echo 0)"

ollama_ver="not installed"
ollama_ok=0
if command -v ollama >/dev/null 2>&1; then
  ollama_ver="$(ollama --version 2>/dev/null | head -n1 || echo unknown)"
  if curl -sf "${OLLAMA_URL:-http://localhost:11434}/api/tags" >/dev/null 2>&1; then
    ollama_ok=1
  fi
fi

tier="$HW_TIER"
recommended_model="$HW_CHAT_MODEL"
recommended_ctx="$HW_CTX_LENGTH"
fit_note="$HW_FIT_NOTE"
embed_model="$GZMO_EMBED_MODEL_DEFAULT"

if (( json == 1 )); then
  printf '{"os":%q,"cpu_model":%q,"cpu_cores":%s,"ram_gb":%s,"gpu_name":%q,"gpu_mib":%s,"tier":%q,"recommended_chat_model":%q,"recommended_embed_model":%q,"recommended_ollama_context_length":%s,"fit_note":%q,"ollama_version":%q,"ollama_reachable":%s}\n' \
    "$os_name" "$cpu_model" "$cpu_cores" "$HW_RAM_GB" "gpu" "$HW_GPU_MIB" \
    "$tier" "$recommended_model" "$embed_model" "$recommended_ctx" "$fit_note" "$ollama_ver" "$ollama_ok"
else
  cat <<EOF
═══════════════════════════════════════════════════
  GZMO hardware report
═══════════════════════════════════════════════════
  OS:           $os_name
  CPU:          $cpu_model ($cpu_cores cores)
  RAM:          ~${HW_RAM_GB} GB
  GPU memory:   ${HW_GPU_MIB} MiB (nvidia-smi total)
  Ollama:       $ollama_ver (reachable: $(if (( ollama_ok )); then echo yes; else echo no; fi))
───────────────────────────────────────────────────
  Tier:         $tier
  Chat model:   $recommended_model
  Embed model:  $embed_model
  OLLAMA_CTX:   $recommended_ctx
  Note:         $fit_note
───────────────────────────────────────────────────
  Next: docs/OLLAMA_TUNING.md → ./scripts/setup-local.sh --print-plan ...
═══════════════════════════════════════════════════
EOF
fi

if [[ -n "$write_vault" ]]; then
  mkdir -p "$write_vault/GZMO"
  {
    echo "# Hardware report"
    echo ""
    echo "Generated: $(date -Iseconds)"
    echo ""
    echo "- OS: $os_name"
    echo "- CPU: $cpu_model ($cpu_cores cores)"
    echo "- RAM: ~${HW_RAM_GB} GB"
    echo "- GPU memory: ${HW_GPU_MIB} MiB"
    echo "- Tier: \`$tier\`"
    echo "- Recommended chat: \`$recommended_model\`"
    echo "- Recommended embed: \`$embed_model\`"
    echo "- Suggested \`OLLAMA_CONTEXT_LENGTH\`: $recommended_ctx"
  } >"$write_vault/GZMO/HARDWARE_REPORT.md"
  echo "Wrote $write_vault/GZMO/HARDWARE_REPORT.md" >&2
fi
