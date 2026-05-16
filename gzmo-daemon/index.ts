/**
 * GZMO Daemon — Core + optional plugins
 *
 *   GZMO_PROFILE=core          inbox, tasks, embeddings, dropzone (default)
 *   GZMO_PLUGINS=dreams,...    Tier-3 plugins (see docs/PLUGINS.md)
 *
 * Usage: bun run index.ts
 */

import { resolve, join, relative, basename } from "path";
import { existsSync, mkdirSync, readdirSync } from "fs";
import { VaultWatcher } from "./src/core/platform/watcher";
import { processTask, infer } from "./src/core/platform/engine";
import { LiveStream } from "./src/core/platform/stream";
import type { PulseLoop } from "./src/plugins/lib/autonomy/pulse.ts";
import { loadPlugins, type PluginHostState } from "./src/plugins/loader.ts";
import { TaskMemory } from "./src/core/platform/memory";
import { safeWriteText } from "./src/core/platform/vault_fs";
import { describeRuntimeProfile, resolveRuntimeProfile } from "./src/core/platform/runtime_profile";
import { EmbeddingsQueue } from "./src/core/rag/embeddings_queue";
import { writeHealth } from "./src/core/platform/health";
import { writeOpsOutputsArtifacts } from "./src/core/platform/ops_outputs_artifact";
import { readBoolEnv } from "./src/core/pipelines/helpers.ts";
import { atomicWriteJson } from "./src/core/platform/vault_fs";
import { invalidateEmbeddingSearchCache } from "./src/core/rag/search";
import { startApiServer } from "./src/core/platform/api_server";
import type { Server } from "bun";
import { recoverStaleProcessing } from "./src/core/platform/boot_recovery";
import { daemonAbort } from "./src/core/platform/lifecycle";
import { TaskSemaphore, readTaskConcurrency } from "./src/core/platform/task_semaphore";
import { sweepOldTraces } from "./src/core/shared/reasoning_trace";
import { startVramProbe, stopVramProbe } from "./src/core/platform/vram_probe";
import { loadConfig } from "./src/core/platform/config";
import { writeBootReport } from "./src/core/platform/boot_report";
import { ensureDropzoneScaffold, resolveDropzoneRoot } from "./src/core/rag/dropzone_paths";

// Rate-limited warnings so a persistent disk/permission error doesn't spam logs.
const _warnedAt = new Map<string, number>();
function warnEvery(key: string, message: string, intervalMs = 60_000): void {
  const now = Date.now();
  const last = _warnedAt.get(key) ?? 0;
  if (now - last < intervalMs) return;
  _warnedAt.set(key, now);
  console.warn(message);
}

// Re-export so any existing tooling that imported `daemonAbort` from index.ts
// keeps working. The canonical home is now ./src/lifecycle.
export { daemonAbort };

// ── Resolve + validate critical config (fail-fast) ─────────
const config = loadConfig();
const VAULT_PATH = config.vaultPath;
const INBOX_PATH = config.inboxPath;
const OLLAMA_API_URL = config.ollamaUrl;
const DROPZONE_ROOT = resolveDropzoneRoot(VAULT_PATH);

// ── Runtime profile (safe mode) ────────────────────────────
const runtime = resolveRuntimeProfile();

// ── Ensure directories exist ───────────────────────────────
for (const dir of [
  join(VAULT_PATH, "GZMO"),
  INBOX_PATH,
  join(VAULT_PATH, "GZMO", "Subtasks"),
  join(VAULT_PATH, "GZMO", "Thought_Cabinet"),
  join(VAULT_PATH, "GZMO", "Issues"),
  join(VAULT_PATH, "GZMO", "Reviews"),
  join(VAULT_PATH, "GZMO", "Reports"),
  join(VAULT_PATH, "wiki", "incoming"),
]) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}
ensureDropzoneScaffold(DROPZONE_ROOT);

// ── Boot ───────────────────────────────────────────────────
console.log("═══════════════════════════════════════════════");
console.log("  GZMO Daemon — Core");
console.log(`  Plugins: ${process.env.GZMO_PLUGINS?.trim() || "(none)"}`);
console.log("═══════════════════════════════════════════════");
console.log(`  Vault:    ${VAULT_PATH}`);
console.log(`  Inbox:    ${INBOX_PATH}`);
console.log(`  Dropzone: ${DROPZONE_ROOT}`);
console.log(`  Model:  ${config.ollamaModel}`);
console.log(`  Ollama: ${OLLAMA_API_URL}`);
console.log(`  Profile:${describeRuntimeProfile(runtime)}`);
console.log("═══════════════════════════════════════════════");

void writeBootReport(VAULT_PATH, { profile: config.profile }).catch(() => {});

// Defaults for the "max finesse" retrieval stack (can be overridden by env).
process.env.GZMO_MULTIQUERY ??= "on";
process.env.GZMO_RERANK_LLM ??= "on";
process.env.GZMO_ANCHOR_PRIOR ??= "on";
process.env.GZMO_MIN_RETRIEVAL_SCORE ??= "0.32";

// ── Ollama Readiness Gate ──────────────────────────────────────
async function waitForOllama(url: string, maxRetries = 10): Promise<boolean> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      const resp = await fetch(`${url}/api/tags`, { signal: AbortSignal.timeout(3000) });
      if (resp.ok) {
        console.log(`[OLLAMA] Connected (attempt ${i + 1})`);
        return true;
      }
    } catch {}
    const delay = Math.min(1000 * Math.pow(2, i), 15000);
    console.log(`[OLLAMA] Waiting for Ollama... retry ${i + 1}/${maxRetries} (${delay}ms)`);
    await new Promise((r) => setTimeout(r, delay));
  }
  return false;
}

// ── Initialize LiveStream ──────────────────────────────────
const stream = new LiveStream(VAULT_PATH);

let pluginHost: PluginHostState = { loaded: [] };
let pulse: PulseLoop | undefined;
stream.log("🟢 Daemon started (core).");

// ── Initialize Task Memory ────────────────────────────────
const memoryPath = join(VAULT_PATH, "GZMO", "memory.json");
const memory = new TaskMemory(memoryPath);
console.log(`[MEMORY] Loaded ${memory.count} entries from memory.json`);

// ── Initialize Embeddings (Vault RAG) ──────────────────────
const embeddingsPath = join(VAULT_PATH, "GZMO", "embeddings.json");
const embeddings = new EmbeddingsQueue(VAULT_PATH, embeddingsPath, OLLAMA_API_URL);

async function bootEmbeddings(): Promise<void> {
  try {
    console.log("[EMBED] Syncing vault embeddings...");
    const store = await embeddings.initByFullSync();
    stream.log(`📚 Vault indexed: ${store.chunks.length} chunks embedded.`);

    if (readBoolEnv("GZMO_ENABLE_TRACE_MEMORY", false)) {
      const { syncTracesIntoStore } = await import("./src/plugins/lib/learning/sync_traces");
      const added = await syncTracesIntoStore(VAULT_PATH, store, OLLAMA_API_URL);
      if (added > 0) {
        invalidateEmbeddingSearchCache(store);
        await atomicWriteJson(VAULT_PATH, "GZMO/embeddings.json", store, 0);
        store.dirty = false;
      }
    }

    if (readBoolEnv("GZMO_LEARNING_BACKFILL", false)) {
      const { backfillLedgerFromPerf } = await import("./src/plugins/lib/learning/build_ledger");
      await backfillLedgerFromPerf(VAULT_PATH, true);
    }
  } catch (err: any) {
    console.warn(`[EMBED] Embedding sync failed (non-fatal): ${err?.message}`);
    console.warn("[EMBED] Vault search will be unavailable until embeddings sync.");
  }
}

// ── Initialize Watcher (declared here, started after Ollama gate) ──
const watcher = new VaultWatcher(INBOX_PATH);

// ── HTTP API server (declared here, started after Ollama gate when enabled) ──
let apiServer: Server<unknown> | undefined;

// R4: track auxiliary watchers / closeables so shutdown can drain them.
let embedWatcher: import("chokidar").FSWatcher | undefined;
let dropzoneWatcher: import("chokidar").FSWatcher | undefined;

let activeTaskCount = 0;
let lastTaskCompletedAt = 0;

// R3: cap concurrent task processing. Default 1 — single-user GPUs almost
// always want one model running at a time. Override via GZMO_TASK_CONCURRENCY.
const taskSem = new TaskSemaphore(readTaskConcurrency());
console.log(`[TASKS] Concurrency limit: ${taskSem.limit}`);

watcher.on("task", async (event) => {
  if (!runtime.enableTaskProcessing) return;
  const action = event.frontmatter?.action ?? "think";
  // Acquire BEFORE bumping the active counter / logging "claimed" so dashboards
  // accurately reflect what's actually running vs queued.
  await taskSem.acquire();
  activeTaskCount++;
  stream.log(`📥 Task claimed: **${event.fileName}** (${action})`);
  try {
    await processTask(event, watcher, pulse, embeddings.getStore(), memory);
    stream.log(`✅ Task completed: **${event.fileName}**`);
    lastTaskCompletedAt = Date.now();
    if (embeddings.getStore()) {
      embeddings.enqueueUpsertFile(`GZMO/Inbox/${event.fileName}.md`);
    }
  } catch (err: any) {
    stream.log(`❌ Task failed: **${event.fileName}** — ${err?.message}`);
  } finally {
    activeTaskCount--;
    taskSem.release();
  }
  if (activeTaskCount === 0) stream.log("💤 Idle. Waiting for tasks...");
});

function autonomyAllowed(): boolean {
  const cooldownMs = Number.parseInt(process.env.GZMO_AUTONOMY_COOLDOWN_MS ?? "20000", 10);
  const cool = Number.isFinite(cooldownMs) ? Math.max(0, cooldownMs) : 20000;
  if (activeTaskCount > 0) return false;
  if (lastTaskCompletedAt && Date.now() - lastTaskCompletedAt < cool) return false;
  return true;
}

async function inboxHasPending(): Promise<boolean> {
  try {
    const inboxDir = join(VAULT_PATH, "GZMO", "Inbox");
    const files = readdirSync(inboxDir).filter((f) => f.endsWith(".md"));
    for (const f of files) {
      try {
        const raw = await Bun.file(join(inboxDir, f)).text();
        if (/^\s*status:\s*pending\s*$/m.test(raw)) return true;
      } catch {}
    }
  } catch {}
  return false;
}

// ── Boot Sequence (Ollama-gated) ──────────────────────────────
(async () => {
  const ollamaReady = await waitForOllama(OLLAMA_API_URL);
  if (!ollamaReady) {
    console.error("[CRITICAL] Ollama unreachable after all retries. Inference and RAG DISABLED.");
    stream.log("🔴 **Ollama unreachable** — inference disabled.");
  } else {
    if (runtime.enableEmbeddingsInitialSync) await bootEmbeddings();
    else console.log("[EMBED] Initial embeddings sync disabled by profile.");
  }

  if (embeddings.getStore() && runtime.enableEmbeddingsLiveSync) {
    const chokidarMod = await import("chokidar");
    const { watch } = chokidarMod;
    embedWatcher = watch([join(VAULT_PATH, "wiki"), join(VAULT_PATH, "GZMO", "Thought_Cabinet")], {
      ignoreInitial: true,
      awaitWriteFinish: { stabilityThreshold: 2000, pollInterval: 500 },
    });
    let embedDebounce: ReturnType<typeof setTimeout> | null = null;
    const pendingFiles = new Set<string>();
    const processEmbedQueue = async () => {
      if (!embeddings.getStore()) return;
      const files = [...pendingFiles];
      pendingFiles.clear();
      for (const fullPath of files) {
        const relPath = relative(VAULT_PATH, fullPath).replace(/\\/g, "/");
        try {
          embeddings.enqueueUpsertFile(relPath);
          console.log(`[EMBED] Live-synced: ${relPath}`);
        } catch {}
      }
    };
    const onFileEvent = (filePath: string) => {
      if (!filePath.endsWith(".md")) return;
      pendingFiles.add(filePath);
      if (embedDebounce) clearTimeout(embedDebounce);
      embedDebounce = setTimeout(processEmbedQueue, 3000);
    };
    embedWatcher.on("change", onFileEvent);
    embedWatcher.on("add", onFileEvent);
    embedWatcher.on("unlink", async (filePath: string) => {
      if (!filePath.endsWith(".md")) return;
      if (!embeddings.getStore()) return;
      const relPath = relative(VAULT_PATH, filePath).replace(/\\/g, "/");
      try {
        embeddings.enqueueRemoveFile(relPath);
        console.log(`[EMBED] Removed embeddings for deleted file: ${relPath}`);
      } catch {}
    });
    console.log("[EMBED] Live-sync watcher started on wiki/ + Thought_Cabinet/");
  } else if (!runtime.enableEmbeddingsLiveSync) {
    console.log("[EMBED] Live-sync watcher disabled by profile.");
  }

  if (runtime.enableInboxWatcher) {
    // R1: Recover tasks left in `processing` after an unclean shutdown.
    // Must run BEFORE watcher.start() so the watcher's initial scan re-dispatches them.
    try {
      const failOnRecover = readBoolEnv("GZMO_RECOVERY_FAIL_ON_RESTART", false);
      const graceMs = Number.parseInt(process.env.GZMO_RECOVERY_GRACE_MS ?? "30000", 10) || 30_000;
      const recovery = await recoverStaleProcessing(INBOX_PATH, { graceMs, failOnRecover });
      if (recovery.recovered.length > 0) {
        const verb = failOnRecover ? "marked failed" : "reset to pending";
        console.log(
          `[RECOVERY] ${recovery.recovered.length} stale 'processing' task(s) ${verb} after restart.`,
        );
        stream.log(`♻️ Boot recovery: ${recovery.recovered.length} stale task(s) ${verb}.`);
      }
      if (recovery.skipped.length > 0) {
        console.log(
          `[RECOVERY] ${recovery.skipped.length} 'processing' task(s) within grace window — left as-is.`,
        );
      }
    } catch (err: any) {
      console.warn(`[RECOVERY] Boot recovery failed (non-fatal): ${err?.message ?? err}`);
    }

    // R5: opt-in trace retention. No-op when GZMO_TRACE_RETAIN_DAYS is unset / 0.
    try {
      const deleted = await sweepOldTraces(VAULT_PATH);
      if (deleted.length > 0) {
        console.log(`[RETENTION] Pruned ${deleted.length} reasoning trace(s) older than retention window.`);
      }
    } catch (err: any) {
      console.warn(`[RETENTION] Trace sweep failed (non-fatal): ${err?.message ?? err}`);
    }

    pluginHost = await loadPlugins({
      vaultPath: VAULT_PATH,
      inboxPath: INBOX_PATH,
      ollamaUrl: OLLAMA_API_URL,
      stream,
      embeddings,
      activeTaskCount: () => activeTaskCount,
      lastTaskCompletedAt: () => lastTaskCompletedAt,
    });
    pulse = pluginHost.pulse;

    watcher.start();

    if (readBoolEnv("GZMO_ENABLE_DROPZONE", true)) {
      try {
        const { startDropzoneWatcher, scanDropzoneOnBoot } = await import("./src/core/rag/dropzone_watcher");
        const dropDeps = {
          vaultPath: VAULT_PATH,
          inboxPath: INBOX_PATH,
          embeddings: embeddings.getStore()
            ? { enqueueUpsertFile: (p: string) => embeddings.enqueueUpsertFile(p), whenIdle: () => embeddings.whenIdle() }
            : undefined,
          log: (m: string) => stream.log(m),
        };
        await scanDropzoneOnBoot(dropDeps);
        dropzoneWatcher = startDropzoneWatcher(dropDeps);
      } catch (err: any) {
        console.warn(`[DROPZONE] Failed to start (non-fatal): ${err?.message ?? err}`);
      }
    } else {
      console.log("[DROPZONE] Disabled (GZMO_ENABLE_DROPZONE=0).");
    }
  } else {
    console.log("[WATCHER] Inbox watcher disabled by profile.");
  }

  if (readBoolEnv("GZMO_API_ENABLED", false)) {
    try {
      apiServer = startApiServer();
    } catch (err: any) {
      console.error(`[API] Failed to start: ${err?.message ?? err}`);
      stream.log(`🔴 API server failed to start: ${err?.message ?? err}`);
    }
  } else {
    console.log("[API] Disabled (set GZMO_API_ENABLED=1 in .env to enable).");
  }

  // T4-A: start the live VRAM probe last. In `auto` mode this is a no-op when
  // nvidia-smi is unavailable, so the env-var bridge keeps working unchanged.
  try {
    const probe = await startVramProbe();
    if (probe.mode === "nvidia-smi") {
      console.log(`[VRAM] Live probe enabled via nvidia-smi (every ${probe.intervalMs}ms).`);
    } else {
      console.log(`[VRAM] Live probe disabled (mode=${probe.mode}); falling back to GZMO_VRAM_* env vars.`);
    }
  } catch (err: any) {
    console.warn(`[VRAM] Probe failed to start (non-fatal): ${err?.message ?? err}`);
  }
})();

// ── Health report (every 60s) ───────────────────────────────
setInterval(async () => {
  const snap = pulse?.snapshot();
  const inboxDir = join(VAULT_PATH, "GZMO", "Inbox");
  const cabinetDir = join(VAULT_PATH, "GZMO", "Thought_Cabinet");
  const quarantineDir = join(VAULT_PATH, "GZMO", "Quarantine");

  let inboxPending = 0, inboxProcessing = 0, inboxCompleted = 0, inboxFailed = 0;
  try {
    const files = readdirSync(inboxDir).filter((f) => f.endsWith(".md"));
    for (const f of files) {
      try {
        const raw = await Bun.file(join(inboxDir, f)).text();
        const m = raw.match(/^\s*status:\s*(\w+)\s*$/m);
        const s = (m?.[1] ?? "").toLowerCase();
        if (s === "pending") inboxPending++;
        else if (s === "processing") inboxProcessing++;
        else if (s === "completed") inboxCompleted++;
        else if (s === "failed") inboxFailed++;
      } catch {}
    }
  } catch {}

  const cabinetNotes = (() => {
    try { return readdirSync(cabinetDir).filter((f) => f.endsWith(".md")).length; } catch { return 0; }
  })();
  const quarantineNotes = (() => {
    try { return readdirSync(quarantineDir).filter((f) => f.endsWith(".md")).length; } catch { return 0; }
  })();

  await writeHealth({
    vaultPath: VAULT_PATH,
    profile: runtime.name,
    ollamaUrl: OLLAMA_API_URL,
    model: process.env.OLLAMA_MODEL ?? "hermes3:8b",
    pulse: snap
      ? {
          tension: snap.tension,
          energy: snap.energy,
          phase: snap.phase,
          alive: snap.alive,
          deaths: snap.deaths,
          tick: snap.tick,
          thoughtsIncubating: snap.thoughtsIncubating,
          thoughtsCrystallized: snap.thoughtsCrystallized,
        }
      : undefined,
    scheduler: {
      plugins: pluginHost.loaded.map((p) => p.id).join(",") || "none",
      embeddingsLiveEnabled: runtime.enableEmbeddingsLiveSync,
    },
    counts: {
      inboxPending,
      inboxProcessing,
      inboxCompleted,
      inboxFailed,
      cabinetNotes,
      quarantineNotes,
    },
  }).catch((err) => {
    warnEvery(
      "write.health",
      `[HEALTH] Failed to write health report (non-fatal): ${err instanceof Error ? err.message : String(err)}`,
      60_000,
    );
  });
}, 60_000);

// ── Graceful Shutdown ──────────────────────────────────────

let shuttingDown = false;

/** Wait until `cond()` returns true OR `timeoutMs` elapses, polling every `intervalMs`. */
async function waitFor(cond: () => boolean, timeoutMs: number, intervalMs = 100): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (!cond()) {
    if (Date.now() >= deadline) return false;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  return true;
}

async function shutdown(signal: string) {
  if (shuttingDown) return; // Idempotent — multiple SIGINTs collapse to one drain.
  shuttingDown = true;

  const drainMs = Number.parseInt(process.env.GZMO_SHUTDOWN_DRAIN_MS ?? "10000", 10) || 10_000;
  console.log(`\n[DAEMON] Received ${signal}. Draining (max ${drainMs}ms)...`);
  stream.log(`🔴 Daemon shutting down (${signal}).`);

  // 1. Stop accepting new work: close watchers FIRST so chokidar doesn't enqueue
  //    fresh "add"/"change" events while we're trying to drain.
  try { await watcher.stop(); } catch (err: any) { console.warn(`[WATCHER] Stop error: ${err?.message ?? err}`); }
  if (embedWatcher) {
    try { await embedWatcher.close(); } catch (err: any) { console.warn(`[EMBED] Stop error: ${err?.message ?? err}`); }
    embedWatcher = undefined;
  }
  if (dropzoneWatcher) {
    try { await dropzoneWatcher.close(); } catch (err: any) { console.warn(`[DROPZONE] Stop error: ${err?.message ?? err}`); }
    dropzoneWatcher = undefined;
  }

  // 2. Stop the HTTP API so no new tasks/searches arrive via the API path.
  if (apiServer) {
    try {
      console.log("[API] Stopping server...");
      apiServer.stop(true);
    } catch (err: any) {
      console.warn(`[API] Stop error: ${err?.message ?? err}`);
    }
  }

  // 3. Wait for in-flight tasks to finish (or hit the drain budget).
  if (activeTaskCount > 0) {
    console.log(`[DAEMON] Waiting for ${activeTaskCount} task(s) to complete...`);
    const tasksDone = await waitFor(() => activeTaskCount === 0, drainMs);
    if (!tasksDone) {
      console.warn(`[DAEMON] ${activeTaskCount} task(s) still running after drain budget — aborting in-flight LLM work.`);
    }
  }

  // 4. Now signal abort: any LLM stream still running will throw cleanly via R2.
  daemonAbort.abort();

  // 5. Wait for the embedding queue to flush (bounded — embeddings are best effort).
  try {
    await Promise.race([
      embeddings.whenIdle(),
      new Promise<void>((r) => setTimeout(r, Math.min(drainMs, 5000))),
    ]);
  } catch { /* ignore */ }

  // 6. Tear down periodic loops + stream.
  stopVramProbe();
  stream.destroy();
  pulse?.stop();

  console.log("[DAEMON] Shutdown complete.");
  process.exit(0);
}
process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
