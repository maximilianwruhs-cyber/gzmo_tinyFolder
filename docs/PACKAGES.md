# Install packages

GZMO ships **two** install packages plus **optional plugins**. All use **Ollama** and the **filesystem inbox** contract.

| Package | `GZMO_PROFILE` | Use when |
|---------|----------------|----------|
| **core** | `core` | Default: inbox tasks, RAG, dropzone |
| **interactive** | `core` + GAH/DSJ flags | Clarification halts on weak evidence |

Runtime profile is always **`GZMO_PROFILE=core`**. Use **`GZMO_PLUGINS`** for Tier-3 modules ([PLUGINS.md](PLUGINS.md)).

## What every package includes

- `VAULT_PATH` (absolute)
- `GZMO_DROPZONE_DIR` (absolute; default `~/Schreibtisch/GZMO-Dropzone` or `~/Desktop/GZMO-Dropzone`)
- `OLLAMA_URL` + `OLLAMA_MODEL` + `GZMO_EMBED_MODEL=nomic-embed-text`
- Model routing **off**
- HTTP API **off** (use `--with-api` if needed for Pi SSE)

Bundles live under [`packages/`](../packages/).

## Install commands

```bash
./scripts/hardware-report.sh
./scripts/setup-local.sh --print-plan --vault /abs/vault --package core
./scripts/setup-local.sh --vault /abs/vault --package core --skip-pi
```

## Deprecated

Install profiles `minimal`, `standard`, and `full` are **not** offered. Scripts alias them to `core` with a warning.

Optional plugins: `./scripts/setup-local.sh --plugins dreams,reasoning,pulse` — see [PLUGINS.md](PLUGINS.md).

After install: `./scripts/verify-local.sh` (hardware + env audit + typecheck).
