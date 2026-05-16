import { join } from "path";
import { existsSync, readdirSync } from "fs";
import { defaultConfig, type ChaosSnapshot } from "../core/shared/types.ts";
import { PulseLoop } from "./lib/autonomy/pulse.ts";
import { safeWriteText } from "../core/platform/vault_fs.ts";
import type { TriggerFired } from "./lib/autonomy/triggers.ts";
import { loadPlugin, parsePluginList, type PluginId } from "./registry.ts";
import type { GzmoPlugin, PluginContext } from "./types.ts";
import type { LiveStream } from "../core/platform/stream.ts";
import type { EmbeddingsQueue } from "../core/rag/embeddings_queue.ts";
import { infer } from "../core/platform/engine.ts";

export interface PluginHostState {
  loaded: GzmoPlugin[];
  pulse?: PulseLoop;
}

export async function loadPlugins(opts: {
  vaultPath: string;
  inboxPath: string;
  ollamaUrl: string;
  stream: LiveStream;
  embeddings: EmbeddingsQueue;
  activeTaskCount: () => number;
  lastTaskCompletedAt: () => number;
}): Promise<PluginHostState> {
  const ids = parsePluginList(process.env.GZMO_PLUGINS);
  if (ids.length === 0) {
    console.log("[PLUGINS] None loaded (set GZMO_PLUGINS=id1,id2 or use packages/plugins/*.env)");
    return { loaded: [] };
  }

  const state: PluginHostState = { loaded: [] };
  let pulse: PulseLoop | undefined;

  const ensurePulse = () => {
    if (pulse) return pulse;
    pulse = new PulseLoop(defaultConfig());
    const snapshotPath = join(opts.vaultPath, "GZMO", "CHAOS_STATE.json");
    pulse.start(snapshotPath);
    pulse.setTriggerDispatch((fired: TriggerFired[], snap: ChaosSnapshot) => {
      for (const f of fired) {
        if (f.action.type === "log") {
          opts.stream.log(f.action.message, {
            tension: snap.tension,
            energy: snap.energy,
            phase: snap.phase,
          });
        }
      }
    });
    state.pulse = pulse;
    return pulse;
  };

  const autonomyAllowed = () => {
    const cooldownMs = Number.parseInt(process.env.GZMO_AUTONOMY_COOLDOWN_MS ?? "20000", 10);
    const cool = Number.isFinite(cooldownMs) ? Math.max(0, cooldownMs) : 20000;
    if (opts.activeTaskCount() > 0) return false;
    const last = opts.lastTaskCompletedAt();
    if (last && Date.now() - last < cool) return false;
    return true;
  };

  const ctxBase = (): Omit<PluginContext, "getPulse" | "setPulse"> => ({
    vaultPath: opts.vaultPath,
    inboxPath: opts.inboxPath,
    ollamaUrl: opts.ollamaUrl,
    stream: opts.stream,
    embeddings: opts.embeddings,
    infer,
    log: (m) => opts.stream.log(m),
    autonomyAllowed,
  });

  for (const id of ids) {
    if (id === "pulse") continue; // pulse is infra; started when another plugin needs it
    try {
      const plugin = await loadPlugin(id);
      if (plugin.needsPulse) ensurePulse();
      const ctx: PluginContext = {
        ...ctxBase(),
        getPulse: () => state.pulse,
        setPulse: (p) => {
          state.pulse = p;
          pulse = p;
        },
      };
      await plugin.register(ctx);
      state.loaded.push(plugin);
      console.log(`[PLUGINS] Registered: ${id}`);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(`[PLUGINS] Failed to load ${id}: ${msg}`);
    }
  }

  if (ids.includes("pulse") && !state.pulse) {
    const plugin = await loadPlugin("pulse");
    const ctx: PluginContext = {
      ...ctxBase(),
      getPulse: () => state.pulse,
      setPulse: (p) => {
        state.pulse = p;
        pulse = p;
      },
    };
    await plugin.register(ctx);
    state.loaded.push(plugin);
  }

  return state;
}
