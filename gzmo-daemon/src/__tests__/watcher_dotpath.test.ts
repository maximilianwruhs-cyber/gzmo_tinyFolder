/**
 * watcher_dotpath.test.ts — Inbox must be watched when vault path contains dot dirs (e.g. ~/.gzmo-vault).
 */
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { VaultWatcher, type TaskEvent } from "../core/platform/watcher";

let root = "";

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "gzmo-watcher-dot-"));
  mkdirSync(join(root, ".hidden-vault", "GZMO", "Inbox"), { recursive: true });
});

afterEach(() => {
  if (root) {
    try {
      rmSync(root, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
    root = "";
  }
});

describe("VaultWatcher dot-prefixed vault paths", () => {
  test("emits task for new pending .md in ~/.something-vault style path", async () => {
    const inbox = join(root, ".hidden-vault", "GZMO", "Inbox");
    const watcher = new VaultWatcher(inbox, 50);

    const seen = new Promise<TaskEvent>((resolve, reject) => {
      const t = setTimeout(() => reject(new Error("timeout waiting for task event")), 8000);
      watcher.on("task", (ev) => {
        clearTimeout(t);
        resolve(ev);
      });
    });

    watcher.start();
    await new Promise((r) => setTimeout(r, 300));

    const fp = join(inbox, "dotpath_probe.md");
    writeFileSync(
      fp,
      `---
status: pending
action: think
---
Say hi.
`,
      "utf8",
    );

    const ev = await seen;
    expect(ev.fileName).toBe("dotpath_probe");
    expect(ev.status).toBe("pending");
    await watcher.stop();
  });
});
