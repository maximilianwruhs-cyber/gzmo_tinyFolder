# Environment bundles

Installers merge these into `gzmo-daemon/.env`:

| Path | Package |
|------|---------|
| [`core/.env.bundle`](core/.env.bundle) | Default product |
| [`interactive/.env.bundle`](interactive/.env.bundle) | Core + clarification flags |
| [`addons/api.env`](addons/api.env) | Optional HTTP API (`--with-api`) |

Apply via:

```bash
./scripts/setup-local.sh --vault /abs/vault --package core
```

Manual merge: set `VAULT_PATH`, `OLLAMA_*`, `GZMO_DROPZONE_DIR`, then append bundle contents.
