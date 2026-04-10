---
name: p4-claude-simplify
description: Reviews all changed files in a Perforce (p4) workspace for code reuse, quality, and efficiency by launching three parallel review agents, then fixes any issues found.
---

# Simplify: Code Review and Cleanup

Review all changed files for reuse, quality, and efficiency. Fix any issues found.

## Prerequisites

If the `p4-workspace-check` skill is available, load it first to validate that the active Perforce client workspace matches the current working directory. If the skill is not available, run `p4 info` and verify that the `Client root` in the output is a parent of the current working directory. If it does not match, warn the user and stop.

## Phase 1: Identify Changes

Run `p4 opened` to list files open in the current workspace. For each opened file, run `p4 diff` to capture the modifications. If no files are open in Perforce, fall back to reviewing the most recently modified files that the user mentioned or that were edited earlier in this conversation.

## Phase 2: Launch Three Review Agents in Parallel

Launch all three subagents concurrently in a single message , each with a general type. Pass each agent the full diff so it has the complete context.

### Agent 1: Code Reuse Review

For each change:

1. **Search for existing utilities and helpers** that could replace newly written code. Look for similar patterns elsewhere in the codebase — common locations are utility directories, shared modules, and files adjacent to the changed ones.
2. **Flag any new function that duplicates existing functionality.** Suggest the existing function to use instead.
3. **Flag any inline logic that could use an existing utility** — hand-rolled string manipulation, manual path handling, custom environment checks, ad-hoc type guards, and similar patterns are common candidates.

### Agent 2: Code Quality Review

Review the same changes for hacky patterns:

1. **Redundant state**: state that duplicates existing state, cached values that could be derived, observers/effects that could be direct calls
2. **Parameter sprawl**: adding new parameters to a function instead of generalizing or restructuring existing ones
3. **Copy-paste with slight variation**: near-duplicate code blocks that should be unified with a shared abstraction
4. **Leaky abstractions**: exposing internal details that should be encapsulated, or breaking existing abstraction boundaries
5. **Stringly-typed code**: using raw strings where constants, enums, or named types already exist in the codebase

### Agent 3: Efficiency Review

Review the same changes for efficiency:

1. **Unnecessary work**: redundant computations, repeated file reads, duplicate network/API calls, N+1 patterns
2. **Missed concurrency**: independent operations run sequentially when they could run in parallel
3. **Hot-path bloat**: new blocking work added to startup or per-request/per-render hot paths
4. **Recurring no-op updates**: state/store updates inside polling loops, intervals, or event handlers that fire unconditionally — add a change-detection guard so downstream consumers aren't notified when nothing changed. Also: if a wrapper function takes an updater/reducer callback, verify it honors same-reference returns (or whatever the "no change" signal is) — otherwise callers' early-return no-ops are silently defeated
5. **Unnecessary existence checks**: pre-checking file/resource existence before operating (TOCTOU anti-pattern) — operate directly and handle the error
6. **Memory**: unbounded data structures, missing cleanup, event listener leaks
7. **Overly broad operations**: reading entire files when only a portion is needed, loading all items when filtering for one

## Phase 3: Fix Issues

Wait for all three agents to complete. Aggregate their findings and fix each issue directly. If a finding is a false positive or not worth addressing, note it and move on — do not argue with the finding, just skip it.

When done, briefly summarize what was fixed (or confirm the code was already clean).