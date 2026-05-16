# Ollama tuning (local stack)

GZMO and Hermes share one Ollama instance. Tune **Ollama** for context and GPU residency; tune **GZMO** retrieval knobs separately ([CORE_PROFILE_TUNING.md](CORE_PROFILE_TUNING.md)).

## Start script

```bash
./scripts/start-ollama-optimized.sh
```

Sets (when supported):

- `OLLAMA_KV_CACHE_TYPE=q8_0`
- `OLLAMA_FLASH_ATTENTION=1`
- `OLLAMA_KEEP_ALIVE=-1`
- `OLLAMA_MAX_LOADED_MODELS=2` (chat + embed)
- `OLLAMA_CONTEXT_LENGTH` from [`scripts/lib/hardware.sh`](../scripts/lib/hardware.sh) when unset

## Context length by tier

Run [`scripts/hardware-report.sh`](../scripts/hardware-report.sh) first (same tiers as `hardware_eval`).

| Tier (`hardware-report`) | Typical hardware | `OLLAMA_CONTEXT_LENGTH` |
|--------------------------|------------------|-------------------------|
| `unified_128gb` | GPU &gt;100 GB MiB (unified) | `262144` |
| `large` | 48 GB+ VRAM or 64 GB+ RAM | `131072` |
| `medium` | 24–48 GB / 32 GB+ RAM | `65536` |
| `cpu_or_small` | default laptop | `32768` |
| `small` | &lt;16 GB RAM | `8192` |

Verify after load:

```bash
ollama ps   # GPU not CPU; CONTEXT matches your choice
```

## Do not use for GZMO “speed”

- `GZMO_ENABLE_MODEL_ROUTING=on` — loads a **second** chat model
- `OLLAMA_DRAFT_MODEL` — not GZMO speculative decoding
- Extra `ollama pull` tags from old `standard`/`full` installers

## Hermes

Point Hermes at the same base URL and model as `OLLAMA_MODEL` in `gzmo-daemon/.env`:

```bash
ollama launch hermes
```

See [AGENT_SETUP_GUIDED.md](AGENT_SETUP_GUIDED.md).
