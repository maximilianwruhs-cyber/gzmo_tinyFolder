import type { GzmoPlugin } from "../types.ts";

const plugin: GzmoPlugin = {
  id: "wiki",
  needsPulse: true,
  register(ctx) {
    let wikiEngine: any;
    let nextWikiTime = Date.now() + 5 * 60 * 1000;
    let nextLintTime = Date.now() + 10 * 60 * 1000;

    import("../lib/autonomy/wiki_engine.ts").then((mod) => {
      const srcPath = new URL("../../", import.meta.url).pathname;
      wikiEngine = new mod.WikiEngine(ctx.vaultPath, srcPath);
    });

    setInterval(async () => {
      const pulse = ctx.getPulse();
      if (!pulse || !wikiEngine) return;
      if (Date.now() < nextWikiTime) return;
      if (!ctx.autonomyAllowed()) return;
      const snap = pulse.snapshot();
      if (!snap.alive || snap.energy < 25) return;
      try {
        const results = await wikiEngine.cycle(ctx.infer, ctx.embeddings.getStore() ?? undefined, ctx.ollamaUrl);
        for (const result of results) {
          ctx.log(`📖 Wiki created: **${result.title}**`);
          pulse.emitEvent({ type: "wiki_consolidated", pageTitle: result.title });
          if (ctx.embeddings.getStore()) {
            ctx.embeddings.enqueueUpsertFile(result.wikiPath.replace(ctx.vaultPath + "/", ""));
          }
        }
      } catch (err: unknown) {
        console.error(`[WIKI] ${err instanceof Error ? err.message : err}`);
      }
      nextWikiTime = Date.now() + 60 * 60 * 1000;
    }, 60_000);

    if (process.env.GZMO_ENABLE_WIKI_LINT !== "0") {
      setInterval(async () => {
        const pulse = ctx.getPulse();
        if (!pulse || Date.now() < nextLintTime) return;
        if (!ctx.autonomyAllowed()) return;
        const snap = pulse.snapshot();
        if (!snap.alive || snap.energy < 25) return;
        try {
          const { runWikiLint } = await import("../../core/rag/wiki_lint.ts");
          await runWikiLint(ctx.vaultPath, { staleDays: 30 });
          ctx.log("🧹 Wiki lint complete");
        } catch (err: unknown) {
          console.error(`[LINT] ${err instanceof Error ? err.message : err}`);
        }
        nextLintTime = Date.now() + 7 * 24 * 60 * 60 * 1000;
      }, 60_000);
    }
  },
};

export default plugin;
