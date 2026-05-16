import type { GzmoPlugin } from "../types.ts";

const plugin: GzmoPlugin = {
  id: "ingest",
  needsPulse: true,
  register(ctx) {
    let ingestEngine: any;
    let nextIngestTime = Date.now() + 2 * 60 * 1000;

    import("../lib/autonomy/ingest_engine.ts").then((mod) => {
      ingestEngine = new mod.IngestEngine(ctx.vaultPath);
    });

    setInterval(async () => {
      const pulse = ctx.getPulse();
      if (!pulse || !ingestEngine) return;
      if (Date.now() < nextIngestTime) return;
      if (!ctx.autonomyAllowed()) return;
      const snap = pulse.snapshot();
      if (!snap.alive || snap.energy < 30) return;
      try {
        const result = await ingestEngine.cycle(ctx.infer, {
          embeddingStore: ctx.embeddings.getStore() ?? undefined,
          ollamaUrl: ctx.ollamaUrl,
        });
        if (result) {
          ctx.log(`📚 Ingested raw source → **${result.title}**`);
          if (ctx.embeddings.getStore()) {
            ctx.embeddings.enqueueUpsertFile(result.summaryWikiPath.replace(ctx.vaultPath + "/", ""));
          }
        }
      } catch (err: unknown) {
        console.error(`[INGEST] ${err instanceof Error ? err.message : err}`);
      }
      nextIngestTime = Date.now() + 15 * 60 * 1000;
    }, 60_000);
  },
};

export default plugin;
