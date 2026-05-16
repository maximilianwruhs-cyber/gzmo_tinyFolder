#!/usr/bin/env bash
#
# local-self-check.sh — Ollama + GZMO self-diagnosis from hardware tier and .env.
#
# Writes $VAULT_PATH/GZMO/SELF_HELP.md so agents and humans have a single "what to do next" file.
# See docs/OLLAMA_TUNING.md and docs/TROUBLESHOOTING_SPARK.md (large-memory appendix).
#
# Usage:
#   ./scripts/local-self-check.sh
#   ./scripts/local-self-check.sh --write-vault
#   ./scripts/local-self-check.sh --heal
#   ./scripts/local-self-check.sh --json
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/hardware.sh
source "$REPO_ROOT/scripts/lib/hardware.sh"

ENV_FILE="${GZMO_ENV_FILE:-$REPO_ROOT/gzmo-daemon/.env}"
write_vault=0
heal=0
json_out=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write-vault) write_vault=1 ;;
    --heal) heal=1 ;;
    --json) json_out=1 ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -f "$ENV_FILE" ]] && set -a && # shellcheck disable=SC1090
  source "$ENV_FILE" 2>/dev/null || true && set +a

hardware_eval
default_ctx="$HW_CTX_LENGTH"
default_chat="$HW_CHAT_MODEL"

ollama_url="${OLLAMA_URL:-http://localhost:11434}"
vault_path="${VAULT_PATH:-}"
model="${OLLAMA_MODEL:-}"
embed_model="${GZMO_EMBED_MODEL:-$GZMO_EMBED_MODEL_DEFAULT}"

issues=()
fixes=()
passes=()
status="PASS"

add_issue() { issues+=("$1"); fixes+=("$2"); status="FAIL"; return 0; }
add_warn() {
  issues+=("$1")
  fixes+=("$2")
  [[ "$status" == "PASS" ]] && status="WARN"
  return 0
}
add_pass() { passes+=("$1"); return 0; }

add_pass "Hardware tier: ${HW_TIER} (~${HW_RAM_GB} GB RAM, ${HW_GPU_MIB} MiB GPU) — suggested chat ${default_chat}, ctx ${default_ctx}"

if ! command -v curl >/dev/null 2>&1; then
  add_issue "curl not installed" "Install curl; then re-run ./scripts/local-self-check.sh"
else
  if curl -sf "${ollama_url}/api/tags" >/dev/null 2>&1; then
    add_pass "Ollama reachable at ${ollama_url}"
  else
    add_issue "Ollama not reachable" \
      "Run: ./scripts/start-ollama-optimized.sh  (or: systemctl start ollama)"
    if (( heal == 1 )); then
      if command -v ollama >/dev/null 2>&1; then
        nohup env OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE:-q8_0}" \
          OLLAMA_FLASH_ATTENTION="${OLLAMA_FLASH_ATTENTION:-1}" \
          OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:--1}" \
          OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-$default_ctx}" \
          ollama serve >/tmp/ollama-local-heal.log 2>&1 &
        sleep 3
        if curl -sf "${ollama_url}/api/tags" >/dev/null 2>&1; then
          add_pass "Heal: started ollama serve in background"
        fi
      fi
    fi
  fi
fi

tags_json=""
if curl -sf "${ollama_url}/api/tags" >/dev/null 2>&1; then
  tags_json="$(curl -sf "${ollama_url}/api/tags" 2>/dev/null || true)"
fi

model_present() {
  local want="$1"
  [[ -n "$tags_json" ]] && echo "$tags_json" | grep -q "\"name\":\"${want}\"" && return 0
  [[ -n "$tags_json" ]] && echo "$tags_json" | grep -q "\"name\":\"${want}:" && return 0
  return 1
}

if [[ -z "$model" ]]; then
  add_warn "OLLAMA_MODEL unset in .env" \
    "Set OLLAMA_MODEL=${default_chat} in gzmo-daemon/.env (run ./scripts/hardware-report.sh)"
  model="$default_chat"
fi

if [[ "$model" == *"coding"* ]] && [[ "$model" == *"nvfp4"* ]]; then
  add_warn "OLLAMA_MODEL looks like *-coding-nvfp4 (known bad pack)" \
    "Use qwen3.6:35b-a3b-nvfp4 not coding-nvfp4 — github.com/ollama/ollama/issues/15866"
fi

if [[ -n "$tags_json" ]]; then
  if model_present "$model"; then
    add_pass "Chat model present: ${model}"
  else
    add_issue "Chat model not pulled: ${model}" \
      "Run: ollama pull ${model}"
    if (( heal == 1 )) && command -v ollama >/dev/null 2>&1; then
      if ollama pull "$model" 2>/dev/null; then
        add_pass "Heal: pulled ${model}"
      fi
    fi
  fi
  if model_present "$embed_model"; then
    add_pass "Embed model present: ${embed_model}"
  else
    add_issue "Embed model not pulled: ${embed_model}" \
      "Run: ollama pull ${embed_model}"
    if (( heal == 1 )) && command -v ollama >/dev/null 2>&1; then
      if ollama pull "$embed_model" 2>/dev/null; then
        add_pass "Heal: pulled ${embed_model}"
      fi
    fi
  fi
fi

if curl -sf "${ollama_url}/api/tags" >/dev/null 2>&1 && [[ -n "$model" ]]; then
  probe="$(curl -sf --max-time 120 "${ollama_url}/api/chat" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with only the digit: what is 2+2?\"}],\"stream\":false,\"options\":{\"num_predict\":16}}" \
    2>/dev/null || true)"
  if [[ -z "$probe" ]]; then
    add_warn "Coherence probe timed out or empty (thinking mode or hung API?)" \
      "Try: ollama run ${model} '2+2=' ; disable thinking"
  elif echo "$probe" | grep -q '4'; then
    add_pass "Coherence probe (2+2) looks sane"
  elif echo "$probe" | grep -qi 'content'; then
    add_warn "Coherence probe returned JSON but not obvious '4'" \
      "Inspect: ollama run ${model} manually"
  else
    add_warn "Coherence probe failed or gibberish" \
      "Re-pull model; see docs/TROUBLESHOOTING_SPARK.md for nvfp4 on large-memory hosts"
  fi
fi

if command -v ollama >/dev/null 2>&1; then
  ps_out="$(ollama ps 2>/dev/null || true)"
  if [[ -n "$ps_out" ]]; then
    if echo "$ps_out" | grep -qiE 'CPU|100% CPU'; then
      add_warn "ollama ps shows CPU offload" \
        "Lower OLLAMA_CONTEXT_LENGTH or use nvfp4; run ollama ps after a test prompt"
    else
      add_pass "ollama ps: no obvious full-CPU offload in listing"
    fi
    if echo "$ps_out" | grep -qE '262144|131072|65536'; then
      add_pass "ollama ps shows large CONTEXT"
    fi
  fi
fi

if [[ ! -f "$ENV_FILE" ]]; then
  add_issue "Missing ${ENV_FILE}" "Run: ./scripts/setup-local.sh --vault /abs/vault --force-env"
elif [[ -z "$vault_path" ]]; then
  add_issue "VAULT_PATH empty in .env" "Set absolute VAULT_PATH in ${ENV_FILE}"
elif [[ ! -d "$vault_path" ]]; then
  add_issue "VAULT_PATH not a directory: ${vault_path}" "Run ./scripts/setup-local.sh --vault ${vault_path} --force-env"
else
  add_pass "VAULT_PATH exists: ${vault_path}"
  drop="${GZMO_DROPZONE_DIR:-}"
  if [[ -z "$drop" ]]; then
    add_warn "GZMO_DROPZONE_DIR unset" \
      "Set to $(default_desktop_dropzone_dir) for desktop drops"
    drop="$(default_desktop_dropzone_dir)"
    if (( heal == 1 )); then
      mkdir -p "$drop"/{_processed,_failed,files,_tmp}
      add_pass "Heal: created default dropzone ${drop}"
    fi
  elif [[ ! -d "$drop" ]]; then
    add_issue "GZMO_DROPZONE_DIR missing: ${drop}" "mkdir -p \"${drop}\"/{_processed,_failed,files,_tmp}"
    if (( heal == 1 )); then
      mkdir -p "$drop"/{_processed,_failed,files,_tmp}
      add_pass "Heal: created ${drop}"
    fi
  else
    add_pass "Dropzone directory exists: ${drop}"
  fi
fi

routing="$(grep -E '^GZMO_ENABLE_MODEL_ROUTING=' "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "' || true)"
fast_m="$(grep -E '^GZMO_FAST_MODEL=' "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "' || true)"
if [[ "${routing,,}" == "on" || "${routing,,}" == "true" || "${routing,,}" == "1" ]]; then
  add_issue "GZMO_ENABLE_MODEL_ROUTING is on" \
    "Set GZMO_ENABLE_MODEL_ROUTING=off; remove GZMO_FAST_MODEL (see docs/PACKAGES.md)"
fi
if [[ -n "$fast_m" && "$fast_m" != "$model" ]]; then
  add_issue "GZMO_FAST_MODEL set to ${fast_m}" \
    "Comment out GZMO_FAST_MODEL — use only OLLAMA_MODEL=${model}"
fi
if [[ -n "${OLLAMA_DRAFT_MODEL:-}" ]]; then
  add_issue "OLLAMA_DRAFT_MODEL=${OLLAMA_DRAFT_MODEL} in environment" \
    "Unset OLLAMA_DRAFT_MODEL; restart Ollama without draft model"
fi

for kv in "GZMO_TOPK:12" "GZMO_EVIDENCE_MAX_SNIPPETS:16" "GZMO_EVIDENCE_MAX_CHARS:2400" "GZMO_LLM_MAX_TOKENS:2048"; do
  key="${kv%%:*}"
  want="${kv##*:}"
  val="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "' || true)"
  if [[ -z "$val" ]]; then
    add_warn "${key} not set (using daemon defaults)" \
      "Add ${key}=${want} — see packages/core/.env.bundle"
  fi
done

if (( json_out == 1 )); then
  printf '{"status":"%s","tier":%q,"issues":%d,"passes":%d}\n' "$status" "$HW_TIER" "${#issues[@]}" "${#passes[@]}"
  exit 0
fi

report_md() {
  local ts
  ts="$(date -Iseconds)"
  cat <<EOF
---
status: informational
type: SELF_HELP
updated_at: ${ts}
overall: ${status}
hardware_tier: ${HW_TIER}
---

# GZMO self-help (machine-generated)

Regenerated by \`./scripts/local-self-check.sh\`. Hardware: tier **${HW_TIER}**, suggested \`${default_chat}\`, ctx **${default_ctx}**.

## Overall: **${status}**

## Passed (${#passes[@]})

EOF
  local p
  for p in "${passes[@]}"; do
    echo "- ${p}"
  done
  if ((${#issues[@]} > 0)); then
    echo ""
    echo "## Issues / warnings (${#issues[@]}) — do these in order"
    echo ""
    local i=1
    local n
    for n in "${!issues[@]}"; do
      echo "${i}. **${issues[$n]}**"
      echo "   - Fix: ${fixes[$n]}"
      i=$((i + 1))
    done
  fi
  cat <<EOF

## Quick commands

\`\`\`bash
./scripts/hardware-report.sh
./scripts/start-ollama-optimized.sh
ollama pull ${model}
ollama pull ${embed_model}
ollama run ${model} "What is 2+2? Reply with only the number."
ollama ps
export GZMO_ENV_FILE="${ENV_FILE}"
./scripts/doctor-agentic.sh --deep
./scripts/local-self-check.sh --heal --write-vault
systemctl --user restart gzmo-daemon
\`\`\`
EOF
}

if (( write_vault == 1 )) && [[ -n "$vault_path" ]] && [[ -d "$vault_path" ]]; then
  mkdir -p "$vault_path/GZMO/Reports"
  help_path="$vault_path/GZMO/SELF_HELP.md"
  report_md > "$help_path"
  ts_file="$(date -Iseconds | tr ':' '-')"
  cp "$help_path" "$vault_path/GZMO/Reports/local_self_check_${ts_file}.md"
  echo "[local-self-check] wrote ${help_path}"
fi

echo "local-self-check: ${status} (${#passes[@]} pass, ${#issues[@]} issue/warn)"
if ((${#issues[@]} > 0)); then
  i=1
  n=0
  for n in "${!issues[@]}"; do
    echo "  ${i}) ${issues[$n]}"
    echo "     → ${fixes[$n]}"
    i=$((i + 1))
  done
fi

case "$status" in
  PASS) exit 0 ;;
  WARN) exit 1 ;;
  FAIL) exit 2 ;;
esac
