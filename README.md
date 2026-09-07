# mico

[한국어](README.ko.md)

A setup utility for Claude Code. `mico install` puts one opinionated, measured
configuration in place — six specialist subagents, three cost-related global
settings, and a deterministic git-safety hook — so that a **plain** Claude Code
session is the default way of working. The original plan-only orchestrator is
still here as `mico orch`, for the cases that justify its price.

## What `install` does

Symbolic links (the cloned `mico/` folder must stay where it is):

| Link | Target |
|---|---|
| `~/.local/bin/mico` | `bin/mico` |
| `~/.claude/agents/*.md` (6 files) | `agents/` |
| `~/.claude/skills/codex-delegate` | `skills/codex-delegate/` |
| `~/.claude/skills/advisor-fable` | `skills/advisor-fable/` |
| `~/.claude/skills/plan-file` | `skills/plan-file/` |
| `~/.claude/skills/review-loop` | `skills/review-loop/` |
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

### The six subagents

`implementer` (Sonnet), `code-investigator` (Sonnet, 1M, per-project memory),
`advisor` (Opus, xhigh, 1M), `web-researcher` (Sonnet), `git-runner` (Sonnet),
`lightweight-runner` (Haiku). In a plain session Claude delegates to them when it
judges that worthwhile; their descriptions say when that is and when it is not,
and deliberately carry no "use proactively" boosters — measured, subagent-heavy
sessions were the largest single contributor to usage.

### Two opt-in skills

The orchestrator's two procedures that are worth keeping without the orchestrator
are available in any plain session as user-invocable skills (Claude cannot trigger
them on its own, so their cost never creeps back in unasked):

- `/plan-file <topic>` — write or update `.mico/plans/<topic>.md`: goal, checkable
  steps each with a verification command, a one-line-per-step log, notes; archive it
  when done. For work that spans several steps or sessions.
- `/review-loop [goal or plan path]` — a bounded adversarial review of finished work:
  a read-only `code-investigator` pass on Opus that tries to refute that the goal is
  met, triage, fixes, hunk-scoped re-checks, three passes at most, both verdicts
  reported. On the benchmark task one such pass cost about as much as the
  implementation, which is why it is opt-in.

### The git guard

`scripts/git-guard.sh` turns the git rules most people keep as advice in
CLAUDE.md into enforcement:

- **denied** — bulk staging: `git add -A`, `git add --all`, `git add .`,
  `git commit -a`. The hook tells the model to stage by explicit path.
- **asks first** — hard-to-undo operations: `git reset --hard`, `git push --force`
  / `-f` / `--force-with-lease`, `git clean -f`, `git branch -D`, `git stash
  drop|clear`. Interactive sessions get a permission prompt even in auto mode;
  headless (`-p`) sessions, where nobody can answer, refuse.

Quoted strings are ignored (a commit message may say "git add -A"), and only
commands that *start* a shell segment count, so `echo git add -A` is not a git
command while `cd repo && git add -A` is. Everything else is allowed.

## Requirements

- **`claude` CLI** (Claude Code) — required.
- **`jq`** — required for the settings merge and both hooks. Without it `install`
  prints the settings to add by hand, the git guard allows everything, and the
  orchestrator guard blocks *all* direct edits.
  Install: macOS `brew install jq` · Debian/Ubuntu `sudo apt install jq` ·
  Fedora `sudo dnf install jq`.
- **`~/.local/bin` on your `PATH`** — so the `mico` command is directly runnable.
- **`codex` CLI** — only for `mico orch --impl codex`, optional.

## Install / update / uninstall

```bash
git clone https://github.com/dongwhee/mico.git
cd mico
./bin/mico install

mico update      # git pull the repo (symlinked installs pick up changes automatically)
mico uninstall   # remove links and hook, restore the managed settings keys
```

After `install`, just run `claude`. There is nothing else to launch.

## Why plain Claude Code is the default

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
setups cost 3–10× a single agent and pay off only for context-heavy or
parallel work. The numbers are one run each on one small task, so treat them as
direction, not precision.

## `mico orch` — the plan-only orchestrator

```bash
mico orch                          # Opus orchestrator, 1M context; Sonnet implementer; Opus xhigh advisor
mico orch --orch sonnet            # lighter orchestrator on Sonnet (also 1M)
mico orch --orch fable --effort medium
mico orch --no-1m                  # 200k context window instead of 1M
mico orch --advisor fable          # advisor agent on Fable instead of Opus
mico orch --impl opus              # force every implementer delegation onto Opus
mico orch --impl codex             # route implementation to codex-delegate (build, xhigh)
mico orch --continue               # remaining args are passed straight through to claude
mico orch --help                   # all options
mico setup                         # align the current project's docs with the orchestrator's conventions
```

Claude runs as an orchestrator: a session-scoped PreToolUse hook blocks its
Edit/Write/NotebookEdit outside a short exemption list (any `*.md`, plan docs
under `.mico/plans/`, its memory docs, report deliverables under `.mico/reports/`
or the session scratchpad), a safe-git allowlist lets it run
status/diff/log/add/commit/stash/fetch/pull without prompts, an observe-only Stop
probe logs turns that end on an announced-but-unperformed action to
`.mico/intent-turn-log.jsonl`, and `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` stops
specialists from re-delegating. Work goes through a plan file
(`.mico/plans/<topic>.md`, template and rules in `prompts/orchestrator-prompt.md`)
and ends with an adversarial `code-investigator` review bounded to three passes.

Use it when edits must be physically blocked, or when a multi-hour autonomous run
needs the plan file's audit trail and the bounded review loop. For ordinary work
the table above is the reason not to.

`--advisor fable` is session-wide; `/advisor-fable [question]` runs a single
advisor consultation on Fable instead. An Agent-tool `model` override inherits the
session's context-window suffix, so under the default `opus[1m]` session the
consultation keeps the large window; only `--no-1m` sessions drop it to 200k.

`mico setup` runs headless Claude in the current project to add a CLAUDE.md note
distinguishing the project's own plans from `.mico/plans/`, gitignore `.mico/`,
and report conflicts in other docs without modifying them. Only needed in
projects where you actually use `mico orch`.
