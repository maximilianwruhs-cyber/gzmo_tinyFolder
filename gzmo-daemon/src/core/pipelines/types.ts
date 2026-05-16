import type { TaskEvent } from "../platform/watcher";
import type { PulseLoop } from "../../plugins/lib/autonomy/pulse";
import type { EmbeddingStore } from "../rag/embeddings";
import type { TaskMemory } from "../platform/memory";
import type { EngineHooks } from "../platform/engine_hooks";

export interface TaskRequest {
  event: TaskEvent;
  pulse?: PulseLoop;
  embeddingStore?: EmbeddingStore;
  memory?: TaskMemory;
  hooks: EngineHooks;
  vaultRoot: string;
}

export interface PipelineContext {
  vaultContext: string;
  systemPrompt: string;
  deterministicAnswer?: string;
  /** If set, engine should markUnbound() instead of inferring. */
  haltReason?: string;
  state: Record<string, any>;
}

export interface TaskPipeline {
  prepare(req: TaskRequest): Promise<PipelineContext>;
  validateAndShape(rawOutput: string, req: TaskRequest, ctx: PipelineContext): Promise<string>;
}
