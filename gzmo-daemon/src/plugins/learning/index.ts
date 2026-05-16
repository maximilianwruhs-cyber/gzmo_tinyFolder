import type { GzmoPlugin } from "../types.ts";

const plugin: GzmoPlugin = {
  id: "learning",
  register(ctx) {
    if (process.env.GZMO_ENABLE_TRACE_MEMORY === "1") {
      void (async () => {
        const store = ctx.embeddings.getStore();
        if (!store) return;
        const { syncTracesIntoStore } = await import("../lib/learning/sync_traces.ts");
        const { invalidateEmbeddingSearchCache } = await import("../../core/rag/search.ts");
        const { atomicWriteJson } = await import("../../core/platform/vault_fs.ts");
        const added = await syncTracesIntoStore(ctx.vaultPath, store, ctx.ollamaUrl);
        if (added > 0) {
          invalidateEmbeddingSearchCache(store);
          await atomicWriteJson(ctx.vaultPath, "GZMO/embeddings.json", store, 0);
          store.dirty = false;
        }
      })();
    }
    console.log("[PLUGINS] learning: trust ledger / strategy tools available via env");
  },
};

export default plugin;
