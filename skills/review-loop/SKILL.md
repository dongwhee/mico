---
name: review-loop
description: Run a bounded adversarial review of finished work — a read-only code-investigator pass on Opus that tries to refute that the goal is met, triage of its findings, fixes, hunk-scoped re-checks, at most three passes — and report both verdicts. User-invocable only. Type /review-loop [goal or plan path] when the work is done and you want it checked before shipping.
user-invocable: true
disable-model-invocation: true
---

# Review loop

Arguments: `$ARGUMENTS` — the goal the work should meet, or the path of the plan file
whose goal it is. If empty, use the goal of the work just completed in this session.

An adversarial pass checks the work before it is reported complete. The reviewer
**advises**; the verdict is yours. The loop is bounded so it terminates: three passes at
most, re-checks scoped to what changed, and a stopping rule that the reviewer's
framing alone cannot extend. On one measured 3-file task a single pass cost about as much
as the implementation itself, which is why this is a skill you invoke rather than a
step that always runs.

## Skip set

Skip the pass for changes that are documentation only — READMEs, docs, plan files — judged on the change as a whole, so one code edit among four doc edits is not in it. Renames are not in it either, of a symbol or of a file: moving either moves its references. Files that define agent or harness behavior are never in it, however small the edit — any `CLAUDE.md` or `AGENTS.md`, anything under `.claude/`, and in the mico repo itself `prompts/`, `agents/`, `skills/`, and the hook scripts under `scripts/`; that carve-out wins over every other entry. A plan that changed nothing but its own file is in it.
When you skip, say so and why. The user invoked you, so if the invocation names the
change explicitly, run the pass anyway and note that the change is in the skip set.

## Checkpoint before every pass

`checkpoint N := git stash create`, falling back to `HEAD` when it returns empty
(clean tree). `git add` new files first, or the stash omits them. Record the SHA in that
pass's Log line or in your message, and name it in the brief: pass 1 diffs the base
commit — recorded at plan activation, or the last commit before the work began: `HEAD` if
none of the work is committed yet, otherwise the parent of the work's first commit — and
pass N diffs checkpoint N−1. A stash SHA is unreachable and prunable — good for the next
re-check, not guaranteed to resolve later; that is acceptable. If a fix landed only in
a gitignored file, name the file and the section in the brief instead of a diff.

## The pass

Delegate to the `code-investigator` agent with `model: "opus"`, read-only. The brief:

- the goal (or plan path) and the diff basis (`git diff <base> <checkpoint 1>` on pass 1,
  `git diff <checkpoint N−1> <checkpoint N>` after, or the file and section when no diff
  can show it);
- "refute that the goal is met"; cite `file:line`;
- report **every** finding first, then a separate PASS/FAIL verdict;
- mark each finding **fail-alone** — would this finding by itself fail the pass — and
  let that set its length: three sentences if fail-alone, one line otherwise;
- give **replacement wording** for findings in prose or instruction files — a fix
  spelled out introduces fewer defects than one you author;
- on a re-check: name the base commit and the previous checkpoint, list the previous
  pass's findings as closed or open, require the label `prior-open`, `new-attributable`,
  or `new-unattributable` on every finding (defined in the agent's own instructions),
  and ask for closed findings as a count.

Ask for everything and filter yourself. Narrowing a brief — "only high-severity", "be
conservative" — is followed literally and suppresses real findings.

## Triage before you fix anything

Read every finding, then sort **blocking** — the goal is not met, or the change is
wrong — from **non-blocking**, which is everything else. Blocking fixes earn a re-check
while the pass count is under the backstop (see "When to stop"); non-blocking ones are
fixed or shipped as recorded residuals, and residuals are listed to the user. The one disagreement you must settle against the artifact: a finding the
reviewer marked fail-alone that you judge non-blocking. Open the cited `file:line` with
a little context and rule on it — the cited lines only, never the whole diff, and never
to hunt for findings the reviewer did not raise.

Apply the fixes yourself, using the reviewer's replacement wording where it gave any.
Delegate to `implementer` only for a fix large enough that you would have delegated
the original change — or, in a `mico orch` session, for any fix outside the guard's
exempt paths, since the guard blocks your own code edits there.

## Re-check

Scoped to what the brief names — the hunks changed since the previous checkpoint, or
the file and section when no diff can show the change — not the closed-findings list,
which misses defects the fix introduced, and not the whole artifact, which never
terminates. Name the previous checkpoint and require the three labels. The reviewer is a fresh agent on every pass, so the brief hands over the base commit and the previous pass's findings marked closed or open; without the base it cannot tell `new-attributable` from `new-unattributable`, and without the findings it cannot assign `prior-open` or return a closed count.

## When to stop

Every re-check is a pass and counts toward the backstop; a pass is one reviewer report, so a delegation that returned none (timeout, relaunch) is not one. A pass ends the loop when none of its findings is both *blocking* and `prior-open` or `new-attributable`; the rest goes to the user with your judgment on each. Blocking findings with either label earn one more round — fix them all, then one re-check — while the pass count is under the backstop. Pass 1 carries no labels: every pass-1 finding counts as `new-attributable`, so triage alone decides. From pass 2 on, a finding the reviewer left unlabeled, gave a label outside the three, or could not place counts as `new-attributable`. Three passes total is the backstop; after the third pass nothing is re-checked: a blocking `prior-open` or `new-attributable` finding whose fix is spelled out — the reviewer's replacement wording, or a change confined to the cited lines — is fixed and reported to the user as fixed but unreviewed, any other blocking finding with those labels is reported open, and every other finding goes to the user whatever its label. A `new-unattributable` label you doubt is settled like a downgrade: open the cited lines against `git diff <base>`, and if the work introduced them treat the finding as `new-attributable`. A `new-unattributable` finding is pre-existing work whatever its severity: report it to the user, neither fixed in this loop nor re-checked — this wins over triage and over the backstop clause above.
Fixes the loop asked for never need a pass of their own, including ones applied to
final-pass residuals after the backstop. Invoked again on work an earlier loop already
reviewed, start a fresh count at pass 1 and hand the reviewer that loop's open findings as
already reported.

## Record the outcome

In the plan's `## Log` (one bullet) or in your message to the user: **both verdicts** —
the reviewer's and yours; divergence is the only evidence that owning the verdict does
anything — the pass count, the finding counts (by label, plus the closed count, from pass 2 on), and the
checkpoint SHAs. Per-finding triage goes in your message to the user, not the Log. Say
plainly what remains open; a finding the user has to dig for was not reported.
