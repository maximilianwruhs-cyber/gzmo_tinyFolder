import type { GzmoPlugin } from "../types.ts";

const plugin: GzmoPlugin = {
  id: "knowledge-graph",
  register() {
    process.env.GZMO_KG_COLLISION ??= "on";
    console.log("[PLUGINS] knowledge-graph: collision gate enabled (GZMO_KG_COLLISION)");
  },
};

export default plugin;
