---
name: codex-delegate
description: Delegate a self-contained unit of work (implement+build+test, or review) to `codex exec` so noisy logs stay out of Claude Code's context and only a small verdict file returns. Use when a task involves running builds/tests that emit lots of output, or when you want an independent second-opinion code review.
user-invocable: true
---

# Delegating to `codex exec`

Claude Code (CC) is the orchestrator; `codex exec` is an **isolated subcontractor**.
Codex does the noisy work (writing code, building, testing, reviewing) inside its
own sandbox. CC receives **only a small verdict file** (~0.5–2 KB) — never the raw
build/test logs. This keeps CC's context from being flooded ("context explosion").

Helper script: `~/.claude/scripts/codex-delegate.sh`

## The one rule that matters

**Never delegate "just write the code."** Bundle the whole unit:
`code + build + test` together (build mode), and review as its own unit (review mode).
If you delegate code alone, CC ends up running the build/test itself and the logs
flood its context — defeating the entire purpose.

## Two modes

### Phase 1 — build (implement + build + test)
```bash
~/.claude/scripts/codex-delegate.sh build <workdir> <workdir>/build_verdict.json "<prompt>"
```
- effort = `high` (override with env `CODEX_DELEGATE_EFFORT`, e.g. set by the `mico --codex-effort` launcher)
- Codex implements, builds, and runs the tests, then writes a JSON verdict:
  `{"success": bool, "tests_passed": int, "tests_failed": int, "notes": str}`
- CC then `Read`s only `build_verdict.json`.

### Phase 2 — review (independent read-only review)
```bash
~/.claude/scripts/codex-delegate.sh review <workdir> <workdir>/review_verdict.md "Review <explicit files>. <checklist>"
```
- effort = `xhigh` (override with env `CODEX_DELEGATE_EFFORT`)
- Read-only **intent**, evidence-based binary gate. Note: under
  `--dangerously-bypass-approvals-and-sandbox` Codex technically has write access —
  "read-only" is enforced by the prompt, not the sandbox. Don't point review mode at a
  dir you can't afford to have touched.
- Verdict's first line is `VERDICT: PASS` or `VERDICT: FAIL`.
- **Always name the files to review explicitly.** Do NOT rely on
  `codex exec review --uncommitted` — it auto-includes large untracked artifacts and
  blows up the context.

### Phase 3 — (optional) structured schema
If you need the review as structured JSON for downstream automation, run a follow-up
`codex exec --output-schema <schema.json> ...` over the markdown verdict. Skip unless needed.

## How CC should use it

1. Decide the unit of work. If it produces build/test noise → delegate it.
2. Call `build`, then `Read` the verdict JSON. If `success:false`, inspect
   `<verdict>.log` (kept in the workdir) only as needed.
3. Optionally call `review` on the changed files; `Read` the markdown verdict.
4. Report to the user from the verdict(s). Do not paste raw logs.

## Sharing CC skills with Codex

Codex obeys CC skill files when you give the **absolute path** in the prompt and tell
it to read first, e.g.:
```
Required skills (read these first): /Users/dongwhee/.claude/skills/<name>/SKILL.md
```
No auto-invocation needed — a read-based reference is enough.

## Writing good prompts (build mode)

Be explicit and verifiable:
- What to create/change (file paths, signatures, requirements).
- How to build and which exact test command to run.
- Any skill files to read (absolute paths).
The script appends the JSON-verdict contract automatically; you don't add it.

## Gotchas (verified on this machine — macOS, codex-cli 0.136.0)

- `--effort` is NOT a `codex exec` flag. Effort is set via
  `-c model_reasoning_effort=high|xhigh` (the script does this for you).
- `--dangerously-bypass-approvals-and-sandbox` is **required** for non-interactive
  runs here; without it codex blocks waiting for approval and never finishes.
- The codex login can expire (401 `token_invalidated`). If a run fails with an auth
  error in the `.log`, re-authenticate: run `! codex login` in the CC prompt.
- This is NOT the codex *plugin*. We use `codex exec` directly — the plugin's review
  mode can hang, so Phase 2 review is done with `codex exec` read-only instead.
