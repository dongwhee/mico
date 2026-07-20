# mico

[한국어](README.ko.md)

A launcher / config bundle that runs Claude Code as a plan-only orchestrator
(Opus by default, paired with an Opus advisor) and delegates the actual work to specialist subagents
(implementer · web-researcher · code-investigator · git-runner ·
lightweight-runner). Everything stays on Claude models by default; implementation
can optionally be routed to the Codex CLI with `--impl codex` (the
`codex-delegate` skill), and only then.

It exists to keep Claude Code token usage under control: the main session stays light (planning and delegation only), heavy or noisy work is routed to cheaper subagents, and reasoning effort is tuned to each task.

## Requirements

- **`claude` CLI** (Claude Code) — required.
- **`jq`** — recommended. Without it the orchestrator guard falls back to blocking
  *all* direct edits, so the orchestrator cannot even fix plan/memory docs itself
  and has to delegate everything.
  Install: macOS `brew install jq` · Debian/Ubuntu `sudo apt install jq` ·
  Fedora `sudo dnf install jq` (or use your package manager).
- **`~/.local/bin` on your `PATH`** — so the `mico` command is directly runnable.
- **`codex` CLI** — only needed for `--impl codex` (Codex delegation), optional.

## Install

```bash
git clone https://github.com/dongwhee/mico.git
cd mico
./bin/mico install
```

`install` only creates symbolic links. Do **not** move or delete the cloned
`mico/` folder — the links point at it.

| Link | Target |
|---|---|
| `~/.local/bin/mico` | `bin/mico` |
| `~/.claude/agents/*.md` (5 files) | `agents/` |
| `~/.claude/skills/codex-delegate` | `skills/codex-delegate/` |
| `~/.claude/scripts/codex-delegate.sh` | `scripts/codex-delegate.sh` |
| `~/.claude/scripts/orchestrator-guard.sh` | `scripts/orchestrator-guard.sh` |

If a real file already exists at one of those paths, it is backed up to
`~/.claude/backups/mico/` before linking (restored on `uninstall`). Install does
not touch the global `~/.claude/settings.json` — the plan-only guard hook is
injected per-session via `--settings` when you run `mico`.

## Usage

```bash
mico                          # Opus orchestrator (effort xhigh + Opus advisor) + implementer on Sonnet 5
mico --orch sonnet            # lighter orchestrator: Sonnet 5 executor + Opus advisor
mico --impl opus              # force every implementer delegation onto Opus
mico --impl codex             # route implementation to codex-delegate (build, xhigh)
mico --codex-effort high      # override codex effort (CODEX_DELEGATE_EFFORT)
mico --continue               # remaining args are passed straight through to claude
mico setup                    # run headless Claude in the current project folder (see below)
mico --help                   # all options
```

`mico setup` launches headless Claude (`claude -p`) in the current project folder
to align that project's docs with mico conventions: it adds a note to CLAUDE.md
distinguishing the project's own plans from the orchestrator's `.mico/plans/`,
adds `.mico/` to `.gitignore`, and reports — without modifying — any conflicts in
other docs (AGENTS.md · docs/ · README). It is idempotent, and recommends
installing `jq` afterwards if it is missing.

The orchestrator is plan-only: a guard hook blocks its Edit/Write/NotebookEdit on
non-markdown files, so for code it analyzes, plans, and delegates (see the routing
table in `prompts/orchestrator-prompt.md`). It can, however, directly edit any
`.md` file and run a safe subset of git
(status/diff/log/add/commit/stash/fetch/pull/...) without prompts;
non-markdown code edits and destructive/outbound git (push, reset --hard,
force-push, rebase) are still delegated to subagents (public `git push` is
additionally gated by the harness).

Plan and memory docs are just markdown instances of that: the orchestrator can
directly Write/Edit the plan document at `<project>/.mico/plans/<topic>.md` and its
own memory docs (`~/.claude/projects/<project>/memory/`). The plan convention is minimal
frontmatter (`goal` / `status` / `created`) plus a checkable `## Steps` section;
only in-progress plans stay in the root directory while finished ones move to
`.mico/plans/archive/` — so the directory listing itself is the active-plan index
(no INDEX file and no grep needed). For details see the "Plan files" section of
`prompts/orchestrator-prompt.md`.

## Update / Uninstall

```bash
mico update      # git pull the repo (symlinked installs pick up changes automatically)
mico uninstall   # remove the links, restore backups
```
