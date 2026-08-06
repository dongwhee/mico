---
name: advisor-fable
description: Run one `advisor` agent consultation on Fable 5 instead of the default Opus. User-invocable only — the user types `/advisor-fable [question]` when they want the heavier model for a specific design/approach decision; the orchestrator never escalates to Fable on its own.
user-invocable: true
disable-model-invocation: true
---

# Fable advisor (one consultation)

The `advisor` agent normally runs on `opus[1m]` (its frontmatter default). This skill
is the **explicit, per-consultation** escalation to Fable 5 — invoked by the user, not
by you. It changes the advisor's MODEL ONLY; when an advisor consultation is
appropriate is unchanged (see "Advisor agent" in the orchestrator prompt).

For a session where *every* advisor call should use Fable, the launcher flag
`mico --advisor fable` already does that — no skill needed.

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
   its decisive reason, and the top risks. Then act on it — update the plan file,
   re-spec the delegation, or bring the disagreement back to the user. A verdict you
   report but ignore is a wasted consultation.

## Context tradeoff (state it if it matters)

The Agent tool's `model` parameter accepts only bare aliases, and the value it
receives **replaces** the agent's frontmatter `opus[1m]` outright. So a Fable
consultation runs with a 200k context window instead of 1M. Scope the brief
accordingly — a plan plus a handful of files is fine; a whole-repo sweep is not. If
the question genuinely needs the 1M window more than it needs Fable, say so and let
the user decide between the two.
