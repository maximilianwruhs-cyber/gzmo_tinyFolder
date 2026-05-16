import type { GzmoPlugin } from "./types.ts";

/** Built-in plugin ids → dynamic import. */
export const PLUGIN_IDS = [
  "pulse",
  "dreams",
  "self-ask",
  "wiki",
  "ingest",
  "prune",
  "reasoning",
  "knowledge-graph",
  "learning",
] as const;

export type PluginId = (typeof PLUGIN_IDS)[number];

const LOADERS: Record<PluginId, () => Promise<{ default: GzmoPlugin }>> = {
  pulse: () => import("./pulse/index.ts"),
  dreams: () => import("./dreams/index.ts"),
  "self-ask": () => import("./self-ask/index.ts"),
  wiki: () => import("./wiki/index.ts"),
  ingest: () => import("./ingest/index.ts"),
  prune: () => import("./prune/index.ts"),
  reasoning: () => import("./reasoning/index.ts"),
  "knowledge-graph": () => import("./knowledge-graph/index.ts"),
  learning: () => import("./learning/index.ts"),
};

export function parsePluginList(raw?: string): PluginId[] {
  const s = (raw ?? "").trim();
  if (!s) return [];
  if (s.toLowerCase() === "all") return [...PLUGIN_IDS];
  const out: PluginId[] = [];
  for (const part of s.split(/[,\s]+/)) {
    const id = part.trim().toLowerCase() as PluginId;
    if (id && LOADERS[id] && !out.includes(id)) out.push(id);
  }
  return out;
}

export async function loadPlugin(id: PluginId): Promise<GzmoPlugin> {
  const mod = await LOADERS[id]();
  return mod.default;
}
