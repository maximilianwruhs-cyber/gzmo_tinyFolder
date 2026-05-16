#!/usr/bin/env bash
# Wrapper — see scripts/platform/install_service.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/scripts/platform/install_service.sh" "$@"
