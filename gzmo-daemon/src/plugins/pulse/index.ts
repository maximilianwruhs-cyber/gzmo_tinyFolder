import { join } from "path";
import { basename } from "path";
import { defaultConfig } from "../../core/shared/types.ts";
import { PulseLoop } from "../lib/autonomy/pulse.ts";
import type { GzmoPlugin } from "../types.ts";

const plugin: GzmoPlugin = {
  id: "pulse",
  needsPulse: true,
  register(ctx) {
    if (!ctx.getPulse()) {
      const pulse = new PulseLoop(defaultConfig());
      pulse.start(join(ctx.vaultPath, "GZMO", "CHAOS_STATE.json"));
      ctx.setPulse(pulse);
    }
    const pulse = ctx.getPulse()!;

    if (process.env.GZMO_ENABLE_DASHBOARD_PULSE !== "0") {
      setInterval(() => {
        if (!pulse) return;
        const snap = pulse.snapshot();
        const v = snap.llmValence >= 0 ? `+${snap.llmValence.toFixed(2)}` : snap.llmValence.toFixed(2);
        ctx.log(
          `💓 T=${snap.tension.toFixed(0)} E=${snap.energy.toFixed(0)}% ${snap.phase} | temp=${snap.llmTemperature.toFixed(2)} val=${v} tok=${snap.llmMaxTokens}`,
        );
        pulse.emitEvent({ type: "heartbeat_fired", energy: snap.energy });
      }, 60_000);
    }
  },
};

export default plugin;
