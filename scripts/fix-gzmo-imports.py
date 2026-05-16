#!/usr/bin/env python3
"""Rewrite relative imports for gzmo clean repo layout."""
from __future__ import annotations
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "gzmo-daemon" / "src"

RAG = {
    "search", "embeddings", "embeddings_queue", "evidence_packet", "citation_formatter",
    "response_shape", "verifier_safety", "self_eval", "local_facts", "query_rewrite",
    "rerank_llm", "bm25", "anchor_index", "adaptive_topk", "lexical_search", "mind_filter",
    "part_citations", "project_grounding", "dropzone_watcher", "dropzone_convert",
    "dropzone_dedup", "dropzone_zip", "dropzone_paths", "wiki_engine", "wiki_index",
    "wiki_log", "wiki_lint", "wiki_ops_index", "wiki_contract", "wiki_graph", "linc_filter",
    "core_wisdom", "core_wisdom_validate",
}

PLATFORM = {
    "vault_fs", "frontmatter", "watcher", "engine", "config", "lifecycle", "boot_recovery",
    "chain_enforce", "engine_hooks", "engine_state", "outputs_registry", "ops_outputs_artifact",
    "inference", "memory", "vault_state_index", "quarantine", "health", "api_server",
    "api_events", "api_types", "auto_tasks", "task_semaphore", "task_types", "yaml_frontmatter",
    "runtime_profile", "boot_report", "self_check_help", "stream", "structured", "guidance_contract",
    "atomic_write", "error_events", "frontmatter", "inference_router",
}

CLARIFICATION = {
    "gah_gate", "route_judge", "shadow_judge", "think_clarification", "judge_score_parser",
    "semantic_noise", "dsj_decision",
}

SHARED = {"types", "perf", "perf_fitness", "fitness_scorer", "eval_harness", "reasoning_trace",
          "kg_collision", "small_model_rules", "html-to-text.d.ts"}

PLUGIN_LIB = {
    "reasoning", "learning", "autonomy", "belief", "knowledge_graph",
}

IMPORT_RE = re.compile(
    r'(from\s+["\'])(\.\./(?:\.\./)?)([^"\']+)(["\'])'
)


def target_prefix(file: Path, mod: str) -> str | None:
    base = mod.split("/")[0].replace(".ts", "")
    if base in PLATFORM:
        return "../platform/"
    if base in RAG:
        return "../rag/"
    if base in CLARIFICATION:
        return "../clarification/"
    if base in SHARED:
        return "../shared/"
    if base in PLUGIN_LIB or mod.startswith("reasoning/") or mod.startswith("learning/"):
        return "../../plugins/lib/"
    if mod.startswith("autonomy/") or mod.startswith("belief/") or mod.startswith("knowledge_graph/"):
        return "../../plugins/lib/"
    if mod.startswith("pipelines/"):
        return "../pipelines/"
    if mod.startswith("tools/"):
        return "../tools/"
    if mod.startswith("platform/"):
        return "../platform/"
    if mod.startswith("rag/"):
        return "../rag/"
    return None


def fix_file(path: Path) -> bool:
    text = path.read_text()
    orig = text
    rel = path.parent

    def repl(m: re.Match) -> str:
        prefix, dots, mod, q = m.group(1), m.group(2), m.group(3), m.group(4)
        # already qualified
        if mod.startswith(("platform/", "rag/", "pipelines/", "clarification/", "shared/", "tools/", "plugins/")):
            return m.group(0)
        mod_clean = mod.replace(".ts", "")
        base = mod_clean.split("/")[0]

        if str(rel).endswith("core/platform"):
            if base in RAG:
                return f'{prefix}../rag/{mod}{q}'
            if base in CLARIFICATION:
                return f'{prefix}../clarification/{mod}{q}'
            if base in SHARED:
                return f'{prefix}../shared/{mod}{q}'
            if base in PLUGIN_LIB or "reasoning/" in mod or "learning/" in mod:
                return f'{prefix}../../plugins/lib/{mod}{q}'
            if base == "pipelines" or mod_clean.startswith("pipelines"):
                return f'{prefix}../pipelines/{mod.split("/",1)[1] if "/" in mod else mod}{q}'
            if base in {"pulse", "dreams", "self_ask", "prune", "ingest_engine", "honeypot_edges", "chaos", "allostasis"}:
                return f'{prefix}../../plugins/lib/autonomy/{mod}{q}'
            if base == "kg_collision":
                return f'{prefix}../shared/{mod}{q}'
            if base in PLATFORM and dots == "../":
                return m.group(0)
        elif "core/rag" in str(rel):
            if base in PLATFORM:
                return f'{prefix}../platform/{mod}{q}'
            if base in CLARIFICATION:
                return f'{prefix}../clarification/{mod}{q}'
            if base in RAG and dots == "../":
                return m.group(0)
            if base in {"pipelines"}:
                return f'{prefix}../pipelines/{mod.split("/",1)[-1]}{q}'
        elif "core/pipelines" in str(rel):
            if base in RAG:
                return f'{prefix}../rag/{mod}{q}'
            if base in PLATFORM:
                return f'{prefix}../platform/{mod}{q}'
            if base in CLARIFICATION:
                return f'{prefix}../clarification/{mod}{q}'
        elif "core/clarification" in str(rel):
            if base in RAG:
                return f'{prefix}../rag/{mod}{q}'
            if base in PLATFORM:
                return f'{prefix}../platform/{mod}{q}'
            if base == "inference_router":
                return f'{prefix}../../plugins/lib/reasoning/inference_router{q}'
        elif "core/shared" in str(rel):
            if base in PLATFORM:
                return f'{prefix}../platform/{mod}{q}'
            if base in RAG:
                return f'{prefix}../rag/{mod}{q}'
            if base == "watcher" or base == "engine":
                return f'{prefix}../platform/{mod}{q}'
        elif "plugins/lib" in str(rel):
            if base in PLATFORM:
                return f'{prefix}../../../core/platform/{mod}{q}'
            if base in RAG:
                return f'{prefix}../../../core/rag/{mod}{q}'
            if base in SHARED:
                return f'{prefix}../../../core/shared/{mod}{q}'
            if base in {"pipelines"}:
                return f'{prefix}../../../core/pipelines/helpers{q}' if "helpers" in mod else f'{prefix}../../../core/pipelines/{mod}{q}'

        return m.group(0)

    text = IMPORT_RE.sub(repl, text)
    if text != orig:
        path.write_text(text)
        return True
    return False


def main() -> None:
    n = 0
    for p in ROOT.rglob("*.ts"):
        if fix_file(p):
            n += 1
            print("fixed", p.relative_to(ROOT))
    print(f"done {n} files")


if __name__ == "__main__":
    main()
