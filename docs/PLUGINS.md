# GZMO plugins

Plugins are **optional Tier-3 subsystems**. Core runs without them.

## Enable at install

```bash
./scripts/setup-local.sh --vault /abs/vault --package core --plugins dreams,self-ask,pulse
```

Or set in `gzmo-daemon/.env`:

```bash
GZMO_PLUGINS=dreams,reasoning
```

## Built-in plugin ids

| Id | Description | Stability |
|----|-------------|-----------|
| `pulse` | Chaos / energy loop (shared by other plugins) | experimental |
| `dreams` | Background dream crystallization | experimental |
| `self-ask` | Autonomous questioning | experimental |
| `wiki` | Wiki consolidation + lint | experimental |
| `ingest` | Raw source ingest loop | experimental |
| `prune` | Pruning vs pulse tension | experimental |
| `reasoning` | ToT / dialectic env hooks in engine | experimental |
| `knowledge-graph` | KG collision gate | experimental |
| `learning` | Ledger / trace tooling | experimental |

## Rules

- Plugins must **not** change `OLLAMA_MODEL` or enable model routing.
- One chat model + `nomic-embed-text` only.
- `GZMO_PROFILE=core` — plugins are not profiles.

## Dev: load all

```bash
GZMO_PLUGINS=all bun run summon
```
