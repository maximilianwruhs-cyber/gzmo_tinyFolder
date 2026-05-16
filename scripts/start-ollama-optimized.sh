#!/usr/bin/env bash
#
# start-ollama-optimized.sh — Start Ollama with a smaller KV cache.
#
# Uses `q8_0` KV cache and enables flash attention by default. Keeps models
# loaded with `OLLAMA_KEEP_ALIVE=-1` to avoid cold starts.
#
# Usage:
#   ./scripts/start-ollama-optimized.sh                # default: ollama serve
#   ./scripts/start-ollama-optimized.sh --port 11500   # extra args forwarded
#
# To make this the default systemd unit:
#   ExecStart=/abs/path/to/scripts/start-ollama-optimized.sh
#
set -euo pipefail

export OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE:-q8_0}"
export OLLAMA_FLASH_ATTENTION="${OLLAMA_FLASH_ATTENTION:-1}"
export OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:--1}"

# Default context from hardware tier when unset (see scripts/hardware-report.sh).
if [[ -z "${OLLAMA_CONTEXT_LENGTH:-}" ]]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -f "$REPO_ROOT/scripts/lib/hardware.sh" ]]; then
    # shellcheck source=lib/hardware.sh
    source "$REPO_ROOT/scripts/lib/hardware.sh"
    export OLLAMA_CONTEXT_LENGTH="$(hardware_recommended_context_length)"
  fi
fi

# Optional: speculative draft (Ollama-native only — NOT used by GZMO).
# Leave UNSET for GZMO: a second chat model (e.g. qwen2.5:0.5b) breaks single-model setup.
if [[ -n "${OLLAMA_DRAFT_MODEL:-}" ]]; then
  echo "[OLLAMA] WARNING: OLLAMA_DRAFT_MODEL=${OLLAMA_DRAFT_MODEL} loads a second chat model." >&2
  echo "[OLLAMA]          GZMO expects only OLLAMA_MODEL + GZMO_EMBED_MODEL. Unset OLLAMA_DRAFT_MODEL." >&2
fi

# Optional: FP8 toggle for RTX 50-series (Ollama build dependent).
# export OLLAMA_CUDA_FP16=0

if ! command -v ollama >/dev/null 2>&1; then
  echo "[OLLAMA] ollama binary not found in PATH" >&2
  exit 127
fi

echo "[OLLAMA] Starting with:"
echo "[OLLAMA]   OLLAMA_KV_CACHE_TYPE=${OLLAMA_KV_CACHE_TYPE}"
echo "[OLLAMA]   OLLAMA_FLASH_ATTENTION=${OLLAMA_FLASH_ATTENTION}"
echo "[OLLAMA]   OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE}"
if [[ -n "${OLLAMA_CONTEXT_LENGTH:-}" ]]; then
  echo "[OLLAMA]   OLLAMA_CONTEXT_LENGTH=${OLLAMA_CONTEXT_LENGTH}"
fi

exec ollama serve "$@"
