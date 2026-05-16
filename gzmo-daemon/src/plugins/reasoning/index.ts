import type { GzmoPlugin } from "../types.ts";

/** Reasoning (ToT, dialectic) is env-gated inside engine/pipelines; plugin documents activation. */
const plugin: GzmoPlugin = {
  id: "reasoning",
  register(ctx) {
    process.env.GZMO_ENABLE_REASONING ??= "on";
    console.log("[PLUGINS] reasoning: ToT/dialectic hooks active when task env flags set");
    void ctx;
  },
};

export default plugin;
