---
description: Quick question answered by haiku — one fast turn, session model untouched
argument-hint: <question>
model: haiku
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, mcp__plugin_context-mode_context-mode__ctx_search, mcp__plugin_context-mode_context-mode__ctx_execute, mcp__plugin_context-mode_context-mode__ctx_execute_file, mcp__plugin_context-mode_context-mode__ctx_batch_execute
---

This is a throwaway side question. Answer it directly and concisely, then stop.

Rules:
- Do NOT touch any task in flight, todo.md, or project files.
- No subagents, no edits, no long exploration. At most one quick lookup if strictly needed.
- Prefer context-mode: ctx_search first (session memory + indexed knowledge), ctx_execute/ctx_execute_file to derive answers from data, ctx_batch_execute for read-only shell gathering. Keep raw output out of the reply — return only the derived answer.
- Full conversation context is available — use it to interpret the question.
- If earlier /qq answers exist in the history, this is a CONTINUATION of that side thread — build on your previous answers, don't restart.
- If the question actually requires real work (edits, multi-step), say so in one line and stop; the user will re-ask on the main model.

Question: $ARGUMENTS
