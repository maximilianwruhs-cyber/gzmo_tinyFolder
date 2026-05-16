/**
 * Fire-and-forget local Ollama/GZMO self-check; writes $VAULT_PATH/GZMO/SELF_HELP.md.
 */

import { existsSync } from "fs";
import { join, resolve } from "path";
import { spawn } from "child_process";
import { readBoolEnv } from "../pipelines/helpers.ts";

export function selfCheckEnabled(): boolean {
  if (process.env.GZMO_SELF_CHECK !== undefined) {
    return readBoolEnv("GZMO_SELF_CHECK", true);
  }
  return readBoolEnv("GZMO_SPARK_SELF_CHECK", true);
}

/** @deprecated Use selfCheckEnabled */
export const sparkSelfCheckEnabled = selfCheckEnabled;

export function repoRootFromDaemon(): string {
  return resolve(import.meta.dir, "..", "..");
}

export function selfHelpPath(vaultPath: string): string {
  return join(vaultPath, "GZMO", "SELF_HELP.md");
}

export function runSelfCheckAsync(opts?: { heal?: boolean }): void {
  if (!selfCheckEnabled()) return;

  const repoRoot = repoRootFromDaemon();
  const script = join(repoRoot, "scripts", "local-self-check.sh");
  if (!existsSync(script)) return;

  const envFile =
    process.env.GZMO_ENV_FILE?.trim() || join(repoRoot, "gzmo-daemon", ".env");

  const args = [script, "--write-vault"];
  if (opts?.heal) args.push("--heal");

  try {
    const child = spawn("bash", args, {
      env: { ...process.env, GZMO_ENV_FILE: envFile },
      detached: true,
      stdio: "ignore",
    });
    child.unref();
  } catch {
    // non-fatal
  }
}

/** @deprecated Use runSelfCheckAsync */
export const runSparkSelfCheckAsync = runSelfCheckAsync;
