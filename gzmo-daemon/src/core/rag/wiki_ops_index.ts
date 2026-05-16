import { join } from "path";
import { safeWriteText } from "../platform/vault_fs.ts";
import { writeOpsOutputsArtifacts } from "../platform/ops_outputs_artifact.ts";

export async function writeOpsOutputsIndex(params: {
  vaultPath: string;
}): Promise<string> {
  // Backwards-compatible entrypoint: delegate to the code-defined registry generator.
  await writeOpsOutputsArtifacts({ vaultPath: params.vaultPath });
  return join("wiki", "entities", "GZMO-Ops-Outputs.md");
}

