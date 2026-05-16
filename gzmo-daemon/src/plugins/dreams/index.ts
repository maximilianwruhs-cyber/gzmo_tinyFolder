import { basename, join } from "path";
import type { GzmoPlugin } from "../types.ts";

const DREAM_BASE_MS = 30 * 60 * 1000;

const plugin: GzmoPlugin = {
  id: "dreams",
  needsPulse: true,
  register(ctx) {
    let dreamsModule: any;
    let nextDreamTime = Date.now() + DREAM_BASE_MS;

    setInterval(async () => {
      const pulse = ctx.getPulse();
      if (!pulse) return;
      if (!dreamsModule) {
        const mod = await import("../lib/autonomy/dreams.ts");
        dreamsModule = { engine: new mod.DreamEngine(ctx.vaultPath) };
      }
      if (Date.now() < nextDreamTime) return;
      if (!ctx.autonomyAllowed()) return;
      const snap = pulse.snapshot();
      if (!snap.alive || snap.energy < 20) return;
      try {
        const store = ctx.embeddings.getStore() ?? undefined;
        const result = await dreamsModule.engine.dream(snap, ctx.infer, store, ctx.ollamaUrl);
        if (result) {
          ctx.log(`🌙 Dream crystallized from **${result.taskFile}**`);
          pulse.emitEvent({ type: "dream_proposed", dreamText: result.insights.slice(0, 200) });
          if (store) {
            ctx.embeddings.enqueueUpsertFile(`GZMO/Thought_Cabinet/${basename(result.vaultPath)}`);
          }
        }
      } catch (err: unknown) {
        console.error(`[DREAM] ${err instanceof Error ? err.message : err}`);
      }
      const snap2 = pulse.snapshot();
      const tensionFactor = 1.0 - (snap2.tension / 100) * 0.5;
      nextDreamTime = Date.now() + Math.round(DREAM_BASE_MS * tensionFactor);
    }, 60_000);
  },
};

export default plugin;
