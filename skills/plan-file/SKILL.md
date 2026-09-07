---
name: plan-file
description: Create or update a plan file for multi-step work at .mico/plans/<topic>.md — a goal, checkable steps each with its verification command, a one-line-per-step log, and notes — and archive it when the work is done. User-invocable only. Type /plan-file <topic> when a task is big enough to deserve an audit trail that outlives the session.
user-invocable: true
disable-model-invocation: true
---

# Plan file

Arguments: `$ARGUMENTS` — the topic (becomes the file name) and, optionally, the goal.
If the arguments are empty, the topic is the work currently on the table.

A plan file is the one artifact of a multi-step task that survives the session: it
records what the goal was, which steps were taken, who did each one, and how each was
verified. It is worth writing when the work spans several steps or files, will be
resumed later, or will be handed to someone who did not see the conversation. A
single fully-specified change does not need one — do the change.

## Where

```
<project>/.mico/plans/
  <topic>.md          # live plans (status: draft | active)
  archive/<topic>.md  # finished plans (status: done)
```

The root directory holds only live plans, so listing it *is* the active-plan index.
Never read `archive/` unless explicitly looking for history. When you list the root and
find a plan already marked `done`, `mv` it into `archive/` before doing anything else.

`.mico/` is normally gitignored. If the team wants the plan in history (the
plan-as-reviewable-artifact practice), commit it deliberately, alongside the code it
describes, and update it in the same commit whenever the implementation departs from it.

## Template

```markdown
---
goal: <one-line goal>
status: draft | active | done
created: <YYYY-MM-DD>
---

## Steps
- [ ] 1. <step> → verify: <command or check>
- [ ] 2. <step> → verify: <command or check>

## Log
- <YYYY-MM-DD> <who>: <what was done> — verify: <command> → <pass|fail>

## Notes
<decisions, constraints, open questions, base commit>
```

## Lifecycle

1. **Draft.** Write the file with `status: draft`. Every step must be verifiable by a
   command or an observable check; a step you cannot verify is not yet a step. Name
   scope (which files or areas), acceptance criteria, and what is out of scope. If a gap
   remains that would change what gets built, ask the user — at most three focused
   questions. Claude Code's Plan Mode is a good place to think the plan through; this
   file is where the result lands.
2. **Activate.** Flip to `status: active` only once the user has confirmed the plan. An
   explicit go-ahead in conversation, or an original request that already fully
   specifies the work, counts as confirmation — don't re-ask then. When you flip it,
   record the current commit (`git rev-parse --short HEAD`) in Notes *before* touching
   anything, so the base really is pre-work; a later review diffs against it.
3. **Work.** Check off each step (`[x]`) when its verification passes, and append one
   Log line for it. A Log entry is **one bullet**, shaped
   `- <date> <who>: <what> — verify: <cmd> → <pass|fail>`, at most three lines. No
   headers, no bold subsections, no per-finding lists inside `## Log`; anything longer
   belongs in Notes, in a commit body, or in your message to the user. The plan is
   re-read before every edit, so a plan that grows into a transcript is paid for on
   every write.
4. **Close.** Before `status: done`, the goal should have gone through a review — the
   `/review-loop` skill is the bounded form of that — unless the change is docs-only,
   and the Log should say which it was. Then set `status: done` and move the file to
   `archive/` with plain `mv` (`git mv` fails on a gitignored path).

## Rules

- One plan file per topic — update it in place rather than spawning new files.
- Steps are records, not prose. Keep the file to what a reader needs to resume the
  work; no padding sections, no summary restating the steps.
- When you have written or updated the plan, act on it: start the first unchecked step
  if the plan is active, or ask the one question that blocks activation. Do not end the
  turn on "I'll start with step 1."
