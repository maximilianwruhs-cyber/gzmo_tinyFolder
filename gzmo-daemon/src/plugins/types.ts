import type { Server } from "bun";
import type { EmbeddingsQueue } from "../core/rag/embeddings_queue.ts";
import type { LiveStream } from "../core/platform/stream.ts";
import type { PulseLoop } from "../plugins/lib/autonomy/pulse.ts";
import type { infer } from "../core/platform/engine.ts";

export interface PluginContext {
  vaultPath: string;
  inboxPath: string;
  ollamaUrl: string;
  stream: LiveStream;
  embeddings: EmbeddingsQueue;
  infer: typeof infer;
  log: (msg: string) => void;
  autonomyAllowed: () => boolean;
  getPulse: () => PulseLoop | undefined;
  setPulse: (p: PulseLoop | undefined) => void;
  apiServer?: Server<unknown>;
}

export interface GzmoPlugin {
  id: string;
  /** When true, loader ensures PulseLoop is started before register(). */
  needsPulse?: boolean;
  register(ctx: PluginContext): Promise<void> | void;
  shutdown?(): Promise<void> | void;
}
