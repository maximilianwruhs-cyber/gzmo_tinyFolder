import { basename } from "path";
import type { GzmoPlugin } from "../types.ts";

const plugin: GzmoPlugin = {
  id: "self-ask",
  needsPulse: true,
  register(ctx) {
    let selfAskModule: any;

    setInterval(async () => {
      const pulse = ctx.getPulse();
      if (!pulse) return;
      if (!selfAskModule) {
        const mod = await import("../lib/autonomy/self_ask.ts");
        const edges = await import("../lib/autonomy/honeypot_edges.ts");
        selfAskModule = new mod.SelfAskEngine(ctx.vaultPath, new edges.JsonlEdgeStore(ctx.vaultPath));
      }
      if (!ctx.autonomyAllowed()) return;
      const snap = pulse.snapshot();
      const store = ctx.embeddings.getStore();
      if (!snap.alive || !store) return;
      if (snap.energy < 30) return;
      try {
        const results = await selfAskModule.cycle(snap, store, ctx.ollamaUrl, ctx.infer);
        for (const result of results) {
          ctx.log(`🔍 Self-Ask (${result.strategy}): ${result.output.slice(0, 80).replace(/\n/g, " ")}`);
          pulse.emitEvent({ type: "self_ask_completed", strategy: result.strategy, result: result.output });
          if (result.vaultPath) {
            ctx.embeddings.enqueueUpsertFile(`GZMO/Thought_Cabinet/${basename(result.vaultPath)}`);
          }
        }
      } catch (err: unknown) {
        console.error(`[SELF-ASK] ${err instanceof Error ? err.message : err}`);
      }
    }, 60_000);
  },
};

export default plugin;
