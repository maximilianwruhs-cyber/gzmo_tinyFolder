import type { GzmoPlugin } from "../types.ts";

const plugin: GzmoPlugin = {
  id: "prune",
  needsPulse: true,
  register(ctx) {
    let pruner: { tick: (tension: number, energy: number) => Promise<void> } | undefined;

    import("../lib/autonomy/prune.ts").then((mod) => {
      pruner = new mod.PruningEngine(ctx.vaultPath);
    });

    setInterval(async () => {
      const pulse = ctx.getPulse();
      if (!pulse || !pruner) return;
      const snap = pulse.snapshot();
      await pruner.tick(snap.tension, snap.energy);
    }, 60_000);
  },
};

export default plugin;
