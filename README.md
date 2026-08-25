# mico

[한국어](README.ko.md)

A launcher / config bundle that runs Claude Code as a plan-only orchestrator
(Opus with a 1M context window by default) and delegates the actual work to specialist subagents
(implementer · advisor · web-researcher · code-investigator · git-runner ·
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
| `~/.claude/agents/*.md` (6 files) | `agents/` |
| `~/.claude/skills/codex-delegate` | `skills/codex-delegate/` |
| `~/.claude/skills/advisor-fable` | `skills/advisor-fable/` |
| `~/.claude/scripts/codex-delegate.sh` | `scripts/codex-delegate.sh` |
| `~/.claude/scripts/orchestrator-guard.sh` | `scripts/orchestrator-guard.sh` |

If a real file already exists at one of those paths, it is backed up to
`~/.claude/backups/mico/` before linking (restored on `uninstall`). Install does
not touch the global `~/.claude/settings.json` — the plan-only guard hook is
injected per-session via `--settings` when you run `mico`.

## Usage

```bash
mico                          # Opus orchestrator, 1M context (effort high) + implementer on Sonnet 5 + advisor agent on Opus xhigh
mico --orch sonnet            # lighter orchestrator on Sonnet 5 (also 1M)
mico --no-1m                  # drop the orchestrator to the 200k context window
mico --advisor fable          # run the advisor agent on Fable 5 instead of Opus
mico --effort xhigh           # raise the orchestrator itself back to xhigh
mico --impl opus              # force every implementer delegation onto Opus
mico --impl codex             # route implementation to codex-delegate (build, xhigh)
mico --codex-effort high      # override codex effort (CODEX_DELEGATE_EFFORT)
mico --continue               # remaining args are passed straight through to claude
mico setup                    # run headless Claude in the current project folder (see below)
mico --help                   # all options
```

`--advisor fable` is session-wide. For a one-off, type `/advisor-fable [question]`
in-session: it runs a single `advisor` consultation on Fable 5 instead of Opus. The
skill is user-invocable only — the orchestrator cannot escalate to Fable on its own,
it can only suggest that you do. Note the tradeoff: an Agent-tool `model` override
replaces the agent's `opus[1m]` default, so a Fable consultation gets a 200k context
window, not 1M.

`mico setup` launches headless Claude (`claude -p`) in the current project folder
to align that project's docs with mico conventions: it adds a note to CLAUDE.md
distinguishing the project's own plans from the orchestrator's `.mico/plans/`,
adds `.mico/` to `.gitignore`, and reports — without modifying — any conflicts in
other docs (AGENTS.md · docs/ · README). It is idempotent, and recommends
installing `jq` afterwards if it is missing.

The orchestrator is plan-only: a guard hook blocks its Edit/Write/NotebookEdit on
everything outside a short exemption list, so for code it analyzes, plans, and delegates (see the routing
table in `prompts/orchestrator-prompt.md`). It can, however, directly edit any
`.md` file, author report deliverables (see below), and run a safe subset of git
(status/diff/log/add/commit/stash/fetch/pull/...) without prompts;
every other file edit and destructive/outbound git (push, reset --hard,
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

Report deliverables are the other exemption. Handing you an HTML page — an audit,
a comparison table, a diagram — is reporting, not implementation, so the
orchestrator writes it itself instead of spending an `implementer` run on it. Two
locations are open, extension-agnostic (`.html`/`.css`/`.js`/data files alike):

- the **session scratchpad** — a `scratchpad/` directory under the system temp
  root (`$TMPDIR`, `/tmp`, `/private/tmp`, `/var/folders`, `/private/var/folders`),
  where Claude Code puts
  its per-session scratch files. This is the default for a page published via the
  built-in `Artifact` tool and handed over as a link. A directory inside your
  project that merely happens to be named `scratchpad/` is *not* exempt — the
  match is anchored to the temp root, not to the working directory, so it holds
  no matter which subdirectory you launched `mico` from.
- any **`.mico/reports/`** directory, when you want the file kept on disk in the
  project — `mico setup` already gitignores `.mico/`, so it stays out of the
  repo's history unless you add it deliberately.

Everything else stays with the `implementer`: HTML that ships as part of the
product is still code. And note the `jq` dependency — without `jq` the guard
falls back to blocking *all* direct edits, report deliverables included.

## Update / Uninstall

```bash
mico update      # git pull the repo (symlinked installs pick up changes automatically)
mico uninstall   # remove the links, restore backups
```
