# mico

[한국어](README.ko.md)

**mico configures Claude Code and then gets out of the way.** `mico install`
puts one opinionated, measured configuration into `~/.claude` — six specialist
subagents, three cost-related global settings, five user-invocable skills, and a
deterministic git-safety hook — and from then on you work the ordinary way: run
`claude`. There is no wrapper, no daemon, and nothing to launch.

That default is a measured conclusion rather than a preference. mico also ships
`mico orch`, a launcher that runs Claude Code as a *plan-only orchestrator* — a
session forbidden to edit files, which delegates every change to a subagent. On
an ordinary 3-file task it cost 3–5× a plain session for the same result
([numbers below](#why-a-plain-session-is-the-default)), so it is opt-in, and the
last section is a guide to the situations that still earn it.

## Quick start

```bash
git clone https://github.com/dongwhee/mico.git
cd mico
./bin/mico install
claude          # the configuration is global; just work
```

`install` works by symlink, so the cloned `mico/` folder must stay where it is.

## What `install` puts in place

Symbolic links:

| Link | Target |
|---|---|
| `~/.local/bin/mico` | `bin/mico` |
| `~/.claude/agents/*.md` (6 files) | `agents/` |
| `~/.claude/skills/plan-file` | `skills/plan-file/` |
| `~/.claude/skills/review-loop` | `skills/review-loop/` |
| `~/.claude/skills/advisor-fable` | `skills/advisor-fable/` |
| `~/.claude/skills/nightshift` | `skills/nightshift/` |
| `~/.claude/skills/codex-delegate` | `skills/codex-delegate/` |
| `~/.claude/scripts/git-guard.sh` | `scripts/git-guard.sh` |
| `~/.claude/scripts/orchestrator-guard.sh` | `scripts/orchestrator-guard.sh` |
| `~/.claude/scripts/codex-delegate.sh` | `scripts/codex-delegate.sh` |

Managed keys merged into `~/.claude/settings.json` (the file is backed up once to
`~/.claude/backups/mico/settings.json` before the first merge; everything else in
it is left alone; re-running `install` is idempotent):

| Key | Value | Why |
|---|---|---|
| `model` | `opus[1m]` | Cheapest current model that handled the benchmark task as well as the others (below). |
| `autoCompactWindow` | `300000` | Sessions above 150k context accounted for ~74% of measured usage; a 1M model otherwise never compacts. Raise to `400000` if compaction feels too frequent. |
| `env.CLAUDE_CODE_SUBAGENT_MODEL` | `sonnet` | Built-in subagents (Explore, Plan, general-purpose) run on Sonnet instead of inheriting Opus. Agents with their own frontmatter `model` keep it — frontmatter outranks the env var. |
| `hooks.PreToolUse` (matcher `Bash`) | `scripts/git-guard.sh` | See below. |

`uninstall` removes the links and the hook entry and puts each managed key back
to what the backup holds (or deletes it if the backup lacked it).

### Six specialist subagents

`implementer` (Sonnet), `code-investigator` (Sonnet, 1M, per-project memory),
`advisor` (Opus, xhigh, 1M), `web-researcher` (Sonnet), `git-runner` (Sonnet),
`lightweight-runner` (Haiku). An ordinary session delegates to them when it
judges that worthwhile; their descriptions say when that is and when it is not,
and deliberately carry no "use proactively" boosters — measured, subagent-heavy
sessions were the largest single contributor to usage.

### Five user-invocable skills

Each runs only when you type its slash command. Claude cannot trigger any of them
on its own (`disable-model-invocation`), so their cost never creeps in unasked:

- **`/plan-file <topic>`** — write or update `.mico/plans/<topic>.md`: goal,
  checkable steps each with a verification command, a one-line-per-step log,
  notes; archive it when done. For work that spans several steps or sessions.
- **`/review-loop [goal or plan path]`** — a bounded adversarial review of
  finished work: a read-only `code-investigator` pass on Opus that tries to
  refute that the goal is met, triage, fixes, hunk-scoped re-checks, three passes
  at most, both verdicts reported. On the benchmark task one such pass cost about
  as much as the implementation, which is why it is opt-in.
- **`/advisor-fable [question]`** — one `advisor` consultation on Fable instead of
  the default Opus: an independent second opinion from a fresh context, for a
  design or approach decision *before* the work — not for reviewing a diff after it.
- **`/nightshift [topic]`** — the pre-flight for an unattended overnight run: read
  what the plan has left, decide with you every question the run would otherwise
  stop to ask, write the answers and the run's contract (branch, commit policy,
  forbidden commands, retry and turn bounds) into the plan file, and hand back the
  one `/goal` line to paste before you leave. The night itself is Claude Code's
  built-in `/goal`, not a mico loop.
- **`/codex-delegate`** — hand a self-contained unit of work (implement + build +
  test, or a review) to the Codex CLI in its own sandbox, so only a small verdict
  file comes back instead of the raw build logs. Requires the `codex` CLI.

`/plan-file` and `/review-loop` are the two procedures lifted out of the
orchestrator prompt: they are the part of `mico orch` worth having at
plain-session price.

### The git guard

`scripts/git-guard.sh` turns the git rules most people keep as advice in
CLAUDE.md into enforcement:

- **denied** — bulk staging: `git add` with `-A`, `--all`, or `.`, and
  `git commit -a`. The hook tells the model to stage by explicit path.
- **asks first** — hard-to-undo operations: `git reset --hard`, `git push --force`
  / `-f` / `--force-with-lease`, `git clean -f`, `git branch -D`, `git stash
  drop|clear`. Interactive sessions get a permission prompt even in auto mode;
  headless (`-p`) sessions, where nobody can answer, refuse.

Quoted strings are ignored (a commit message may quote a denied command), and
only commands that *start* a shell segment count, so `echo git add ...` is not a
git command while `cd repo && git add ...` is. Everything else is allowed.

## Requirements

- **`claude` CLI** (Claude Code) — required.
- **`jq`** — required for the settings merge and both hooks. Without it `install`
  prints the settings to add by hand, the git guard allows everything, and the
  orchestrator guard blocks *all* direct edits.
  Install: macOS `brew install jq` · Debian/Ubuntu `sudo apt install jq` ·
  Fedora `sudo dnf install jq`.
- **`~/.local/bin` on your `PATH`** — so the `mico` command is directly runnable.
- **`codex` CLI** — only for `/codex-delegate` and `mico orch --impl codex`, optional.

## Install / update / uninstall

```bash
mico update      # git pull the repo (symlinked installs pick up changes automatically)
mico uninstall   # remove links and hook, restore the managed settings keys
```

## Why a plain session is the default

The same 3-file backend task (add input validation to a YAML parser and its
missing tests, in a real FastAPI repo) was run once per configuration, headless,
each in its own git worktree, with the tests executed in the project's CI
container. All four produced correct, passing implementations.

| Configuration | API cost (est.) | Wall time | API calls (main / subagents) | Peak main context |
|---|---|---|---|---|
| plain Claude Code, Opus 5 | $0.71 | 142 s | 13 / 0 | 44k |
| plain Claude Code, Fable 5.1 | $1.04 | 154 s | 6 / 0 | 43k |
| `mico orch --orch fable --effort medium` | $2.03 | 575 s | 11 / 38 | 50k |
| `mico orch` (Opus orchestrator, Sonnet implementer) | $3.28 | 702 s | 18 / 62 | 60k |

The orchestrator's promised saving — a light main context — did not appear: its
main context peaked *higher* than the plain runs, and its largest cost item was
the Opus review pass. This matches Anthropic's own guidance that multi-agent
setups cost 3–10× a single agent and pay off only for context-heavy or parallel
work. The numbers are one run each on one small task, so treat them as direction,
not precision.

## `mico orch` — the optional orchestrator mode

### What it is

In an orchestrator session the main Claude **cannot edit code**. A session-scoped
PreToolUse hook blocks its `Edit`/`Write`/`NotebookEdit` outside a short exemption
list (any `*.md`, plan docs under `.mico/plans/`, its own memory docs, report
deliverables under `.mico/reports/`, and the session scratchpad), so every code
change has to be written as a spec and handed to a specialist subagent that
carries it out and verifies it. Around that, the session:

- keeps the work in a plan file, `.mico/plans/<topic>.md` — goal, steps, a
  verification command per step, a log (template and rules in
  `prompts/orchestrator-prompt.md`);
- ends with an adversarial `code-investigator` review bounded to three passes;
- allows safe git (`status`/`diff`/`log`/`add`/`commit`/`stash`/`fetch`/`pull`)
  without permission prompts, while destructive git keeps prompting;
- sets `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`, so specialists cannot re-delegate;
- logs turns that announce an action without performing it to
  `.mico/intent-turn-log.jsonl` (observe-only — it never blocks).

None of this is global: the hook and the permissions are injected into that one
session via `--settings`, and the rest of your Claude Code setup is untouched.

### When it fits

- **Direct edits must be impossible, not merely discouraged.** The block is a
  hook, so it holds however the session drifts — worth its price in a repo where
  an unreviewed direct edit is expensive.
- **A long autonomous run you will not be watching.** The plan file is the audit
  trail of what was attempted and how each step was verified, and the bounded
  review loop is a stopping check that does not depend on the model's own sense
  of being finished.
- **Context-heavy or parallelizable work** — a survey across many files, or
  several independent subtasks that can fan out to specialists at once. This is
  the shape where multi-agent overhead actually buys something.
- **You want the review pass to be part of the run**, rather than something you
  remember to invoke at the end.

### When it does not

- **Ordinary work on a handful of files.** The table above: several times the
  cost and roughly 4–5× the wall clock for the same result — and the light main
  context it promises did not materialize.
- **Work you steer turn by turn.** The spec-and-delegate round trip adds latency
  to every change, and you lose the direct edits that make interactive work fast.
- **You mainly wanted the discipline.** A plain session plus `/plan-file` and
  `/review-loop` gives you the plan file and the adversarial review at
  plain-session price. Start there; reach for `mico orch` only when the guard
  itself is the point.

### Running it

```bash
mico orch                          # Opus orchestrator, 1M context; Sonnet implementer; Opus xhigh advisor
mico orch --orch sonnet            # lighter orchestrator on Sonnet (also 1M)
mico orch --orch fable --effort medium
mico orch --no-1m                  # 200k context window instead of 1M
mico orch --advisor fable          # advisor agent on Fable instead of Opus
mico orch --impl opus              # force every implementer delegation onto Opus
mico orch --impl codex             # route implementation to codex-delegate (build mode)
mico orch --codex-effort high      # codex reasoning effort (default xhigh under --impl codex)
mico orch --continue               # unrecognized args are passed straight through to claude
mico orch --help                   # all options
```

`--advisor fable` is session-wide; `/advisor-fable [question]` runs a single
advisor consultation on Fable instead, and works in a plain session too. An
Agent-tool `model` override inherits the session's context-window suffix, so
under the default `opus[1m]` session the consultation keeps the large window;
only `--no-1m` sessions drop it to 200k.

### `mico setup`

```bash
mico setup      # align the current project's docs with the orchestrator's conventions
```

Runs headless Claude in the current project to add a CLAUDE.md note distinguishing
the project's own plans from `.mico/plans/`, gitignore `.mico/`, and report
conflicts in other docs without modifying them. Interactively it also offers to
set up `code-review-graph` (a local code-index MCP server) for the project — it
installs and builds the index, and the new project MCP server needs one approval
on the next interactive launch. Only needed in projects where you actually use
`mico orch`.
