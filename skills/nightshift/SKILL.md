---
name: nightshift
description: Pre-flight for an unattended overnight run — read what the plan has left, decide every question the run would otherwise stop to ask, write the answers and the run's contract into the plan file, and hand back the one `/goal` line that keeps the session working while you are gone. User-invocable only. Type /nightshift [topic or plan path] before you leave for the day.
user-invocable: true
disable-model-invocation: true
---

# Nightshift (pre-flight for an unattended run)

Arguments: `$ARGUMENTS` — the topic, or the path of the plan file the night should work
through. If empty, use the single live plan in `.mico/plans/`; if there is more than one,
ask which.

**This skill does not run the night.** Claude Code's built-in `/goal` does: after every
turn a small model checks your condition, and while it is unmet Claude starts another turn
instead of returning control to you. `/goal` is a command the user types, not one Claude
can invoke — so this skill's whole job is the pre-flight, and it ends by handing back the
line to paste. What it produces is a plan file the run can execute without a human, and a
condition sentence short enough to paste and complete enough to survive compaction.

The night is a plain session. Under `mico orch` the guard blocks the main agent's own
edits, so every code change at 2am would have to go through `implementer`; if that is the
intent, say so in `## Night run`.

## What an unattended run cannot do

Everything below is why the pre-flight exists. Each one is a stall that costs the whole
night, not a recoverable error:

- **`AskUserQuestion` is never auto-approved — in any permission mode, `bypassPermissions`
  included.** A question at 2am waits until morning. So does `ExitPlanMode`.
- **Hard-to-undo git stalls too.** `~/.claude/scripts/git-guard.sh` escalates
  `reset --hard`, force-push (including `--force-with-lease`), `clean -f`, `branch -D`, and
  `stash drop|clear` to an *ask* decision, which prompts (and waits) in an interactive
  session. Bulk staging — `git add -A` / `.` and `git commit -a` — is denied outright.
- **The other mico skills cannot be invoked at night.** `/review-loop`, `/advisor-fable`,
  `/plan-file` and `/codex-delegate` are all `disable-model-invocation`, so the Skill tool
  refuses them (`mico orch --impl codex` routes codex work by other means, and this skill
  does not assume an orchestrator session). Review is the morning's job, and the plan file
  is edited directly.

## 1. The plan is the night's only instruction set

The night runs off `.mico/plans/<topic>.md`, not off this conversation: an eight-hour run
compacts several times, and the conversation is what compaction drops. If no plan file
exists, write one now — the template and the lifecycle rules live in
`~/.claude/skills/plan-file/SKILL.md`. Activation follows plan-file's rules with one
addition: for a night, the go-ahead must be explicit and step-by-step even where plan-file
would accept the original request as confirmation. Show the user the exact list of steps the
night will run and get that go-ahead before flipping `status: active`. Without it there is
no night — hand back no `/goal` line. Record the base commit in Notes at activation.

If the plan is already `status: active`, that confirmation still has to happen for the
night: list the remaining steps the run will execute and get an explicit go-ahead. An old
activation is not authorisation to run those steps unattended, and without the go-ahead you
hand back no `/goal` line.

Read the remaining steps and settle two things:

- **Every remaining step needs a verification command.** A step whose result nobody can
  check is not runnable unattended: either give it one, or take it out of the night's scope
  and say in Notes that it was deferred.
- **The remaining work is worth a night.** One or two small steps are not — say so and
  finish them now. An unattended run bills like any other session and consumes the same
  subscription usage, and nobody is watching it spend.

## 2. Sweep the plan for every question the night would ask

Go step by step through what is left and collect the points where the run would otherwise
need a human. The kinds that actually come up:

- **Design forks** — two viable approaches with no clear winner, or an interface whose
  shape the plan left open.
- **Scope boundaries** — whether a step also touches the neighbouring module, whether a
  found-along-the-way defect is in or out.
- **Failure policy** — how many attempts a step gets before the run gives up on it, and
  what happens to the steps that depend on it.
- **Hard-to-undo actions** — a dependency added, a file or table dropped, a generated
  artifact committed, anything outbound.
- **The turn cap** — how many turns the night gets before it stops, reports, and marks
  whatever it did not reach.
- **Commit policy and branch**, unless the defaults in section 3 already fit.

Ask them with `AskUserQuestion`, batched (at most four questions per call), each option
saying what the run will do if it is chosen. Ask everything you would have asked at 2am:
a question skipped here becomes either a stalled night or a guess nobody authorised. Do
not spend the user's last five minutes on questions the plan or the repo already answers —
only genuine forks.

## 3. Write the contract into the plan file

Two sections, in the plan file itself, because that is what the run re-reads. Answers that
live only in this conversation are gone by the third compaction.

```markdown
## Decisions
- step 3 — <the question>: <the answer>. If <the assumption> turns out false: mark the
  step BLOCKED (see below) and start the next step.

## Night run
- branch: night/<topic>-<YYYY-MM-DD>, cut from <base sha>
- commit: one commit per step whose verification passed, staged by explicit path
- forbidden: push, force-push (including `--force-with-lease`), reset --hard, clean -f,
  branch -D, stash drop/clear, `git add -A` / `.`, `git commit -a`, dependency changes not
  listed in Decisions, edits outside <scope>
- retries: 2 per step, then BLOCKED and move on; a step whose prerequisite is BLOCKED is
  BLOCKED without attempts unless Decisions says otherwise
- stop: every step done or BLOCKED, or <N> turns — at the cap, mark every step not yet
  DONE as BLOCKED (out of turns), then write the report and print NIGHTSHIFT DONE
- on finish: write `REVIEW PENDING` in the plan's `## Notes` and leave `status: active`
- report: .mico/reports/nightshift-<topic>-<YYYY-MM-DD>.md
```

The rule that keeps the night moving, and the one to state in `## Decisions` verbatim:
**when the run meets something Decisions does not cover, it neither asks nor guesses past
the record — it marks the step BLOCKED and starts the next step.** One blocked step costs
one step; a question costs the night.

A blocked step is marked in two places, because the plan's step list has no third checkbox
state: leave the step `[ ]`, append `(BLOCKED)` to its step text, and add one Log bullet in
plan-file's shape — `- <date> night: <step> blocked, <reason> — verify: <cmd> → fail`.
Nothing else about the blocked step goes in `## Log`; a longer explanation goes in `## Notes`
and in the morning report.

Defaults, unless the sweep replaced them: a `night/<topic>-<date>` branch cut before you
leave (so `main` is untouched and the morning's `git log` is the audit trail), one commit
per passing step, and never a push. Cut the branch first, then stash or commit whatever is
already in the working tree — uncommitted edits follow you onto the night branch and end up
inside the night's commits, and committing them before you cut lands them on the base
branch. Prefer the stash; if you commit them instead, record that commit as the base sha,
not the pre-cut HEAD.

## 4. Hand back the `/goal` line

Claude cannot type a slash command. Print the line for the user to paste, self-contained —
the condition is re-sent to the evaluator every turn, so it is the one instruction
guaranteed to outlive compaction. The evaluator reads only the transcript — it runs no
commands and opens no files — so every clause must be something the run *states* in the
conversation, which is what the `NIGHTSHIFT DONE` sentinel is for. Keep it under 4,000
characters:

```
/goal The transcript contains a line "NIGHTSHIFT DONE" that lists every step of
.mico/plans/<topic>.md as DONE or BLOCKED, each with its verify command and result or the
reason no verification ran, and states that
.mico/reports/nightshift-<topic>-<date>.md was written. Follow that plan file's
## Decisions and ## Night run sections. Never ask a question and never run a forbidden
command: if Decisions does not cover a judgment, mark the step BLOCKED with the reason and
start the next step. Report the turn count each turn; at <N> turns, mark every step not yet
done as BLOCKED (out of turns), write the report, and print NIGHTSHIFT DONE.
```

Then say, one line each:

- **Permissions.** `/goal` does not change the permission mode, and even Auto mode still
  prompts for anything the settings do not already allow. Before handing back the line, list
  the commands the night will run (build, test, lint, git) and check each against the rules
  actually in force — `~/.claude/settings.json` and `~/.claude/settings.local.json`, the
  project's `.claude/settings.json` and `.claude/settings.local.json`, and the per-project
  rules under `projects["<cwd>"].allowedTools` in `~/.claude.json` — then show the user the
  uncovered ones together with the `Bash(<prefix>:*)` rules to add. A `deny` match is as
  fatal as a missing `allow`, and one prompt on one unusual command at 2am costs the whole
  night.
- **Keep the machine awake** — on macOS, `caffeinate -i` in another terminal. A sleeping
  laptop is a stopped run.
- **The spend bound is soft.** `--max-budget-usd` and `--max-turns` are print-mode (`-p`)
  flags and do not apply to an interactive session; the turn clause works only because the
  run reports its own count each turn, and a compacted transcript can lose that. The hard
  stops are the condition being met, the unrecoverable errors in section 5, and the usage
  limit — size the night's scope accordingly.

## 5. What ends the night on its own

Say these to the user, so a missing morning report is diagnosable rather than mysterious:

- The evaluator judges the condition **met**, or **impossible** — either way the goal
  clears and the transcript records which.
- An **unrecoverable error** clears the goal: authentication failure, exhausted credits, a
  context overflow auto-compaction could not clear, or an unavailable model. Rate limits
  and overloaded servers are *not* in this set — they leave the goal active.
- **No tool use for several turns** stops the loop with the goal still set; it resumes on
  the next prompt.

And, if you come back to the machine: `/goal clear`, or `/clear`.

## 6. The morning

The report at `.mico/reports/nightshift-<topic>-<date>.md` holds what the night is judged
on: steps completed with the verification command and its result, steps BLOCKED with the
reason and what would unblock them, decisions that were used and any whose assumption
turned out false, and the commits made.

The plan stays `status: active` with `REVIEW PENDING` in Notes. Unattended work is exactly
the case the adversarial pass exists for, and only the user can start it: the morning's
first move is `/review-loop <plan path>` — unless the night's whole output is in
review-loop's skip set, in which case record the skip and its reason in the Log.

## Rules

- One night per plan. A second `/nightshift` on the same plan replaces the `## Night run`
  section and appends to `## Decisions` — it does not open a second contract.
- The night's scope is the plan's remaining steps. Do not widen it here; a step the user
  has not seen is a step nobody authorised.
- Plan-file's "act on it" rule does not apply here: activation at pre-flight time is
  followed by the `/goal` line, not by step 1.
- Do not write the report yourself at pre-flight time, and do not check off steps the night
  has not run. The pre-flight's only outputs are the two plan sections, the branch, and the
  line to paste.
