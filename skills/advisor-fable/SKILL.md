---
name: advisor-fable
description: Run one `advisor` agent consultation on Fable instead of the default Opus. User-invocable only — the user types `/advisor-fable [question]` when they want the heavier model for a specific design/approach decision; Claude never escalates to Fable on its own.
user-invocable: true
disable-model-invocation: true
---

# Fable advisor (one consultation)

The `advisor` agent normally runs on `opus[1m]` (its frontmatter default). This skill
is the **explicit, per-consultation** escalation to Fable (the `fable` alias, currently
Fable 5.1) — invoked by the user, not by you. It changes the advisor's MODEL ONLY; when
an advisor consultation is appropriate is unchanged: before activating a plan, when
choosing between approaches, or when work is stuck — not for post-hoc diff review.

For an orchestrator session where *every* advisor call should use Fable, the launcher
flag `mico orch --advisor fable` already does that — no skill needed.

## What to do

1. **Fix the question.** The invocation's arguments are the question or topic. If
   they are empty, use the decision currently on the table (the plan you are about to
   activate, the approach you are weighing, the thing that is stuck). If that is
   genuinely ambiguous, ask the user one question before spending a Fable run.
2. **Write the brief.** Include: the specific question, the plan file path
   (`.mico/plans/<topic>.md`) if one exists, and `file:line` pointers to the code that
   matters. The advisor reads the repo itself — don't paste large code blocks, and
   don't hand it "review everything" (see the context note below).
3. **Delegate one consultation:**
   ```
   Agent(subagent_type: "advisor", model: "fable", prompt: <brief>)
   ```
   `model: "fable"` is mandatory — omit it and the agent silently runs its Opus
   default, which defeats the whole invocation. One agent per invocation: do not fan
   out several Fable advisors over the same question.
4. **Report and act.** Relay the verdict (proceed / proceed-with-changes / rethink),
   its decisive reason, and **every** risk the advisor raised, each with the
   replacement wording it gave — the advisor was told not to drop minor risks, so
   don't drop them here either. If the user has to decide before anything is applied,
   put the full list somewhere that outlives the turn: the plan's Notes, or
   `.mico/reports/advisor-<topic>.md`. Then act on it — update the plan file, re-spec
   the delegation, or bring the disagreement back to the user. A verdict you report
   but ignore is a wasted consultation, and a risk you summarized away is lost.

## Context window (only matters in a 200k session)

The Agent tool's `model` parameter takes a bare alias, and the subagent inherits the
main session's context-window suffix: measured on Claude Code 2.1.263, an override of
`"opus"` dispatched as `claude-opus-5[1m]` when the main session ran on `opus[1m]` and
as plain `claude-opus-5` when the main session ran on bare `opus`. So under the default
`opus[1m]` session the Fable consultation keeps the large window. Only when the session
itself is on a 200k model (`--no-1m`, or a bare alias) does the consultation run at
200k — scope the brief accordingly then, and say so if the question needs the window
more than it needs Fable.
