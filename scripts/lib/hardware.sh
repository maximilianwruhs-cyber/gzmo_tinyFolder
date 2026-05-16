# hardware.sh — RAM/VRAM tier detection and Ollama model helpers (all platforms).
# Source from repo scripts: source "$REPO_ROOT/scripts/lib/hardware.sh"

readonly GZMO_CHAT_MODEL_NVFP4="qwen3.6:35b-a3b-nvfp4"
readonly GZMO_CHAT_MODEL_BF16="qwen3.6:35b-a3b"
readonly GZMO_EMBED_MODEL_DEFAULT="nomic-embed-text"

# Set by hardware_eval (safe to call repeatedly).
HW_TIER="${HW_TIER:-cpu_or_small}"
HW_CHAT_MODEL="${HW_CHAT_MODEL:-hermes3:8b}"
HW_CTX_LENGTH="${HW_CTX_LENGTH:-32768}"
HW_GPU_MIB="${HW_GPU_MIB:-0}"
HW_RAM_GB="${HW_RAM_GB:-0}"
HW_FIT_NOTE="${HW_FIT_NOTE:-}"

hardware_gpu_mib() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' MiBGB\r' || echo 0
  else
    echo 0
  fi
}

hardware_ram_gb() {
  if [[ -r /proc/meminfo ]]; then
    local ram_kb
    ram_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
    echo $(( (ram_kb + 512 * 1024) / (1024 * 1024) ))
  else
    echo 0
  fi
}

# Classify machine and set HW_* globals. Tiers: small | cpu_or_small | medium | large | unified_128gb
hardware_eval() {
  HW_GPU_MIB="$(hardware_gpu_mib)"
  HW_RAM_GB="$(hardware_ram_gb)"
  HW_TIER="cpu_or_small"
  HW_CHAT_MODEL="hermes3:8b"
  HW_CTX_LENGTH="32768"
  HW_FIT_NOTE="Laptop/small GPU — hermes3:8b or override with --ollama-model."

  if [[ "${HW_GPU_MIB:-0}" -gt 100000 ]] 2>/dev/null; then
    HW_TIER="unified_128gb"
    HW_CHAT_MODEL="$GZMO_CHAT_MODEL_NVFP4"
    HW_CTX_LENGTH="262144"
    HW_FIT_NOTE="~128 GB unified GPU memory — nvfp4 + large context."
  elif [[ "${HW_GPU_MIB:-0}" -ge 48000 ]] 2>/dev/null || [[ "${HW_RAM_GB:-0}" -ge 64 ]]; then
    HW_TIER="large"
    HW_CHAT_MODEL="$GZMO_CHAT_MODEL_NVFP4"
    HW_CTX_LENGTH="131072"
    HW_FIT_NOTE="48 GB+ VRAM or 64 GB+ RAM — nvfp4 may fit; confirm with ollama ps."
  elif [[ "${HW_GPU_MIB:-0}" -ge 24000 ]] 2>/dev/null || [[ "${HW_RAM_GB:-0}" -ge 32 ]]; then
    HW_TIER="medium"
    HW_CHAT_MODEL="qwen3:32b"
    HW_CTX_LENGTH="65536"
    HW_FIT_NOTE="24–48 GB class — qwen3:32b or smaller quant."
  elif [[ "${HW_RAM_GB:-0}" -lt 16 ]]; then
    HW_TIER="small"
    HW_CHAT_MODEL="hermes3:8b"
    HW_CTX_LENGTH="8192"
    HW_FIT_NOTE="Under 16 GB RAM — avoid large MoE models."
  fi
}

hardware_recommended_chat_model() {
  hardware_eval
  echo "$HW_CHAT_MODEL"
}

hardware_recommended_context_length() {
  hardware_eval
  echo "$HW_CTX_LENGTH"
}

hardware_tier_needs_nvfp4_pull() {
  hardware_eval
  [[ "$HW_TIER" == "unified_128gb" || "$HW_TIER" == "large" ]]
}

default_desktop_dropzone_dir() {
  local home="${HOME:-}"
  [[ -n "$home" ]] || { echo "/tmp/GZMO-Dropzone"; return; }
  for desk in "$home/Schreibtisch" "$home/Desktop"; do
    if [[ -d "$desk" || -d "$(dirname "$desk")" ]]; then
      echo "$desk/GZMO-Dropzone"
      return
    fi
  done
  echo "$home/GZMO-Dropzone"
}

ollama_model_present() {
  local tag="${1:-}"
  [[ -n "$tag" ]] || return 1
  command -v ollama >/dev/null 2>&1 || return 1
  ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$tag"
}

ollama_version_ok_for_nvfp4() {
  local ver raw major minor
  raw="$(ollama --version 2>/dev/null | head -n1 || true)"
  ver="${raw#*version }"
  ver="${ver%% *}"
  [[ "$ver" =~ ^[0-9]+\.[0-9]+ ]] || return 0
  major="${ver%%.*}"
  minor="${ver#*.}"; minor="${minor%%.*}"
  [[ "${major:-0}" -gt 0 ]] && return 0
  [[ "${major:-0}" -eq 0 && "${minor:-0}" -ge 15 ]] && return 0
  echo "hardware: WARNING: Ollama ${ver:-unknown} may be too old for ${GZMO_CHAT_MODEL_NVFP4}. Upgrade: https://ollama.com/download (need 0.15+)." >&2
  return 1
}

pull_nvfp4_chat_model() {
  local tag pulled=0
  ollama_version_ok_for_nvfp4 || true

  if ollama_model_present "$GZMO_CHAT_MODEL_NVFP4"; then
    echo "hardware: chat model already present: ${GZMO_CHAT_MODEL_NVFP4}" >&2
    echo "$GZMO_CHAT_MODEL_NVFP4"
    return 0
  fi

  echo "hardware: pulling ${GZMO_CHAT_MODEL_NVFP4} (tag is lowercase 35b)…" >&2
  if ollama pull "$GZMO_CHAT_MODEL_NVFP4"; then
    if ollama_model_present "$GZMO_CHAT_MODEL_NVFP4"; then
      echo "$GZMO_CHAT_MODEL_NVFP4"
      return 0
    fi
    pulled=1
  fi

  echo "hardware: WARNING: ${GZMO_CHAT_MODEL_NVFP4} not available after pull." >&2
  echo "  - Exact tag: ${GZMO_CHAT_MODEL_NVFP4} (not qwen3.6:35B-a3b-nvfp4)" >&2
  echo "  - Upgrade Ollama to 0.15+: https://ollama.com/download" >&2
  echo "  - Fallback: ${GZMO_CHAT_MODEL_BF16} (~70 GB download)" >&2

  if ollama_model_present "$GZMO_CHAT_MODEL_BF16"; then
    echo "hardware: using already-pulled ${GZMO_CHAT_MODEL_BF16}" >&2
    echo "$GZMO_CHAT_MODEL_BF16"
    return 0
  fi

  echo "hardware: pulling fallback ${GZMO_CHAT_MODEL_BF16}…" >&2
  if ollama pull "$GZMO_CHAT_MODEL_BF16" && ollama_model_present "$GZMO_CHAT_MODEL_BF16"; then
    echo "$GZMO_CHAT_MODEL_BF16"
    return 0
  fi

  echo "hardware: ERROR: could not pull nvfp4 MoE chat model." >&2
  if (( pulled == 0 )); then
    echo "hardware: Check network and: ollama pull ${GZMO_CHAT_MODEL_NVFP4}" >&2
  fi
  echo "$GZMO_CHAT_MODEL_NVFP4"
  return 1
}

pull_chat_model_for_tier() {
  hardware_eval
  local model="$HW_CHAT_MODEL"
  if hardware_tier_needs_nvfp4_pull; then
    pull_nvfp4_chat_model || model="$HW_CHAT_MODEL"
  elif command -v ollama >/dev/null 2>&1; then
    echo "hardware: pulling ${model}…" >&2
    ollama pull "$model" || true
  fi
  echo "$model"
}

pull_embed_model() {
  local tag="${GZMO_EMBED_MODEL_DEFAULT}"
  echo "hardware: pulling embed model ${tag}…" >&2
  ollama pull "$tag" || true
  echo "$tag"
}

install_pi_coding_stack() {
  local repo_root="${1:-}"
  [[ -n "$repo_root" ]] || return 1
  local ext_dir="$repo_root/.pi/extensions"
  local skill_dst="${PI_SKILLS_DIR:-$HOME/.pi/skills}/gzmo-daemon"

  if [[ -f "$ext_dir/package.json" ]]; then
    if command -v bun >/dev/null 2>&1 || [[ -x "${HOME:-}/.bun/bin/bun" ]]; then
      echo "hardware: installing Pi coding agent deps (.pi/extensions)…" >&2
      (cd "$ext_dir" && bun install) || echo "hardware: WARNING: bun install in .pi/extensions failed" >&2
    else
      echo "hardware: WARNING: Bun missing — run: cd $ext_dir && bun install" >&2
    fi
  fi

  if [[ -f "$repo_root/.pi/extensions/gzmo-tinyfolder.ts" ]]; then
    mkdir -p "${HOME:-/tmp}/.pi/agent/extensions" 2>/dev/null || true
    ln -sfn "$repo_root/.pi/extensions/gzmo-tinyfolder.ts" "${HOME}/.pi/agent/extensions/gzmo-tinyfolder.ts" 2>/dev/null || \
      echo "hardware: WARNING: could not symlink Pi extension to ~/.pi/agent/extensions" >&2
  fi

  if [[ -x "$repo_root/scripts/install_pi_skill.sh" ]]; then
    "$repo_root/scripts/install_pi_skill.sh" || \
      echo "hardware: WARNING: Pi shell skill install failed (optional)" >&2
  fi

  echo "hardware: Pi — open this repo in Pi, or: cd $repo_root && npx pi (after bun install in .pi/extensions)" >&2
  echo "hardware: export GZMO_ENV_FILE=\"$repo_root/gzmo-daemon/.env\"" >&2
}

print_single_model_reminder() {
  local chat_model="${1:-$GZMO_CHAT_MODEL_NVFP4}"
  hardware_eval
  cat >&2 <<EOF

────────────────────────────────────────────────────
  Large-memory host: use ONE chat model for GZMO
  Tier:         ${HW_TIER} (~${HW_RAM_GB} GB RAM, ${HW_GPU_MIB} MiB GPU reported)
  OLLAMA_MODEL=${chat_model}
  Embeddings:   ${GZMO_EMBED_MODEL_DEFAULT} (GZMO_EMBED_MODEL)
  Do not enable GZMO_FAST_MODEL, GZMO_ENABLE_MODEL_ROUTING=on, or OLLAMA_DRAFT_MODEL.
  Suggested OLLAMA_CONTEXT_LENGTH=${HW_CTX_LENGTH}
  Verify: ollama ps  →  one chat model @ expected CONTEXT
────────────────────────────────────────────────────
EOF
}
