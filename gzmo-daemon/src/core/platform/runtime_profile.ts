import { readBoolEnv } from "../pipelines/helpers.ts";

export type GzmoProfileName = "core" | "heartbeat";

export interface RuntimeProfile {
  name: GzmoProfileName;
  enableInboxWatcher: boolean;
  enableTaskProcessing: boolean;
  enableEmbeddingsInitialSync: boolean;
  enableEmbeddingsLiveSync: boolean;
}

function parseProfileName(raw?: string): GzmoProfileName {
  const v = (raw ?? "").trim().toLowerCase();
  if (v === "heartbeat") return "heartbeat";
  if (v === "full" || v === "interactive" || v === "minimal" || v === "standard") {
    console.warn(
      `[PROFILE] GZMO_PROFILE=${v} is deprecated — use GZMO_PROFILE=core and GZMO_PLUGINS=... (see docs/PLUGINS.md)`,
    );
  }
  return "core";
}

export function defaultRuntimeProfile(name: GzmoProfileName): RuntimeProfile {
  if (name === "heartbeat") {
    return {
      name,
      enableInboxWatcher: false,
      enableTaskProcessing: false,
      enableEmbeddingsInitialSync: false,
      enableEmbeddingsLiveSync: false,
    };
  }
  return {
    name: "core",
    enableInboxWatcher: true,
    enableTaskProcessing: true,
    enableEmbeddingsInitialSync: true,
    enableEmbeddingsLiveSync: true,
  };
}

export function resolveRuntimeProfile(): RuntimeProfile {
  const base = defaultRuntimeProfile(parseProfileName(process.env.GZMO_PROFILE));
  return {
    ...base,
    enableInboxWatcher: readBoolEnv("GZMO_ENABLE_INBOX_WATCHER", base.enableInboxWatcher),
    enableTaskProcessing: readBoolEnv("GZMO_ENABLE_TASK_PROCESSING", base.enableTaskProcessing),
    enableEmbeddingsInitialSync: readBoolEnv("GZMO_ENABLE_EMBEDDINGS_SYNC", base.enableEmbeddingsInitialSync),
    enableEmbeddingsLiveSync: readBoolEnv("GZMO_ENABLE_EMBEDDINGS_LIVE", base.enableEmbeddingsLiveSync),
  };
}

export function describeRuntimeProfile(p: RuntimeProfile): string {
  return `${p.name} (inbox=${p.enableInboxWatcher ? "on" : "off"}, tasks=${p.enableTaskProcessing ? "on" : "off"}, embed=${p.enableEmbeddingsInitialSync ? "on" : "off"})`;
}
