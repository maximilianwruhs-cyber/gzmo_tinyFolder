# AGENTS — GZMO

## Golden path

```bash
./scripts/hardware-report.sh
./scripts/setup-local.sh --vault /abs/vault --package core --force-env
./scripts/local-self-check.sh --heal --write-vault
cd gzmo-daemon && bun run summon
```

## Rules

- `VAULT_PATH` must be **absolute** in `gzmo-daemon/.env`
- `GZMO_PROFILE=core` at runtime; use **`GZMO_PLUGINS`** for Tier-3 modules ([docs/PLUGINS.md](docs/PLUGINS.md))
- Install package **`interactive`** adds GAH/DSJ env flags only
- One chat model (`OLLAMA_MODEL`) + `nomic-embed-text` — no routing, no `OLLAMA_DRAFT_MODEL`

## Do not

- Enable `GZMO_ENABLE_MODEL_ROUTING` or `GZMO_FAST_MODEL`
- Pull extra chat models beyond hardware report recommendation

## Stuck?

Read `$VAULT_PATH/GZMO/SELF_HELP.md` after `./scripts/local-self-check.sh --write-vault`
