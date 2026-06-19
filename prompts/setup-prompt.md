# mico setup — align this project's docs with mico conventions

You are a one-shot, non-interactive setup task running in the current project's
working directory. Align this project's docs with mico conventions, then print a
summary and exit. Do exactly the three items below — nothing more.

## Hard rules
- Make ALL edits with the **Edit** / **Write** tools. Find and read files with
  **Read** / **Grep** / **Glob**. **NEVER use Bash to edit files** (no `sed -i`,
  `echo >>`, `tee`, heredocs, `patch`). Bash edits are not permitted here and will
  silently fail.
- Be **surgical and idempotent**: read the existing content first, and add a note
  or line ONLY if it is not already present. Match the project's existing doc
  style and language. Running this task twice must not duplicate anything.

## Item 1 — plan disambiguation note in CLAUDE.md (CONDITIONAL, WRITE)
First check whether this project has its OWN planning convention, i.e. either:
- a `plans/` directory exists, OR
- `CLAUDE.md` has a section about plans / TODOs / backlog.

If NEITHER is true, **skip this item** (do nothing). If there is **no `CLAUDE.md`
at all, skip this item** — do NOT create or fabricate a CLAUDE.md.

If a plan convention DOES exist and `CLAUDE.md` exists:
- Read `CLAUDE.md`. If it already contains a note distinguishing the project's own
  plans from the mico orchestrator's `.mico/plans/`, do nothing (idempotent — look
  for an existing mention of `.mico/plans/`).
- Otherwise add a single short note (adapt wording and language to the project's
  style) conveying: the project's own `plans/` (or equivalent) is the project's
  backlog; the mico orchestrator's working plans live separately in `.mico/plans/`
  and are unrelated. Place it near the project's existing plan section.
- NEVER delete or rewrite the project's own plan docs — only add this one-line
  distinction.

## Item 2 — `.gitignore` += `.mico/` (WRITE)
Ensure `.mico/` is ignored:
- Read `.gitignore` if it exists. If a line for `.mico` / `.mico/` is already
  present, do nothing (idempotent).
- Otherwise append a `.mico/` line. If `.gitignore` does not exist, create it
  containing the single `.mico/` line.

## Item 3 — scan other docs for conflicts (REPORT-ONLY, NO WRITES)
Scan `AGENTS.md`, anything under `docs/`, and `README` for DIRECT conflicts with
mico conventions (e.g. instructions that contradict the `.mico/plans/` working-plan
convention or the orchestrator/subagent delegation model). **Do NOT edit these
files** — only list any conflicts you find in the summary for a human to handle.

## Final summary (print, then exit)
Print a concise summary covering:
- **Written**: which files changed and what was added (or "nothing written").
- **Skipped**: what was skipped and why (e.g. no CLAUDE.md, no plan convention,
  line already present).
- **Conflicts to review**: any other-doc conflicts detected in item 3, or "none".
