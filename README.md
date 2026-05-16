# GZMO

Local vault daemon: **Markdown inbox** + **Ollama** + optional **plugins**.

- **Core:** `think` / `search` / `chain`, hybrid RAG with `[E#]` citations, desktop dropzone.
- **Plugins:** autonomy / reasoning modules — only when listed in `GZMO_PLUGINS`.

## Prerequisites

- Ubuntu Linux (or similar)
- [Bun](https://bun.sh)
- [Ollama](https://ollama.com)

## Install

```bash
./scripts/hardware-report.sh
./scripts/setup-local.sh --vault /absolute/path/to/vault --package core --force-env
cd gzmo-daemon && bun install   # setup-local runs this if Bun is on PATH
```

Optional plugins:

```bash
./scripts/setup-local.sh --vault /abs/vault --package core --plugins dreams,pulse --force-env
```

Interactive package (GAH / DSJ clarification, no extra daemon code):

```bash
./scripts/setup-local.sh --vault /abs/vault --package interactive --force-env
```

## Run

```bash
./scripts/start-ollama-optimized.sh   # or system ollama
export GZMO_ENV_FILE="$(pwd)/gzmo-daemon/.env"
cd gzmo-daemon && bun run summon
```

## Verify

```bash
./scripts/local-self-check.sh --write-vault
./scripts/verify-local.sh
```

Golden task: `$VAULT_PATH/GZMO/Inbox/test.md` with `status: pending`, `action: think`, body `Say hello in one sentence.` → `status: completed`.

## Layout

| Path | Role |
|------|------|
| `gzmo-daemon/src/core/` | Always-on daemon |
| `gzmo-daemon/src/plugins/` | Optional plugins (`GZMO_PLUGINS`) |
| `packages/core/` | Default `.env` bundle |
| `packages/plugins/` | Per-plugin env snippets |

Docs: [docs/PACKAGES.md](docs/PACKAGES.md) · [docs/PLUGINS.md](docs/PLUGINS.md) · [docs/OLLAMA_TUNING.md](docs/OLLAMA_TUNING.md) · [AGENTS.md](AGENTS.md)
