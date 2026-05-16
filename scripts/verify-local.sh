#!/usr/bin/env bash
# verify-local.sh — Post-install checks (no Ollama required for all steps).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${GZMO_ENV_FILE:-$REPO_ROOT/gzmo-daemon/.env}"

echo "== hardware report =="
"$REPO_ROOT/scripts/hardware-report.sh" || true

echo ""
echo "== core env audit =="
if [[ -f "$ENV_FILE" ]]; then
  "$REPO_ROOT/scripts/audit-core-env.sh" --env-file "$ENV_FILE"
else
  echo "skip: no $ENV_FILE"
fi

echo ""
echo "== typecheck =="
( cd "$REPO_ROOT/gzmo-daemon" && bun run typecheck )

echo ""
echo "== ollama (optional) =="
if curl -sf "${OLLAMA_URL:-http://localhost:11434}/api/tags" >/dev/null 2>&1; then
  echo "Ollama reachable"
  ollama ps 2>/dev/null || true
else
  echo "Ollama not reachable (start before golden task)"
fi

echo ""
echo "verify-local: done"
