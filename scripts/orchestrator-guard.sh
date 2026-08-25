#!/usr/bin/env bash
#
# orchestrator-guard.sh — PreToolUse hook for mico's plan-only orchestrator.
#
# Blocks Edit/Write/NotebookEdit for the MAIN orchestrator agent only, while
# allowing SUBAGENTS (implementer, ...) to edit files — that's the whole point
# of mico's delegation design.
#
# How we tell them apart: a subagent's PreToolUse payload carries a top-level
# "agent_id" (and "agent_type") field; the main agent's payload does not. Both
# share the same session_id (subagents run in-process), so session_id is NOT a
# usable discriminator — "agent_id" is. (Verified by clean-room experiment.)
#
# Exemption: the main orchestrator IS allowed to Write/Edit (a) plan documents
# under any ".mico/plans/" directory, (b) memory documents under
# "~/.claude/projects/<project>/memory/", (c) ANY "*.md" file (markdown is
# always editable directly — docs/READMEs/notes need no delegation), (d) report
# deliverables under any ".mico/reports/" directory (user-facing HTML reports
# the orchestrator authors itself), and (e) files under a "scratchpad/" segment
# that resolve under the SYSTEM TEMP ROOT — i.e. the Claude Code session
# scratchpad (e.g. "/private/tmp/claude-<uid>/<project>/<session>/scratchpad/"
# on macOS, "/tmp/claude-<uid>/.../scratchpad/" on Linux), not an in-project
# directory that merely happens to be named "scratchpad". The payload carries
# a "tool_input.file_path" (and "cwd" to resolve relative paths). We resolve
# the target lexically — make it absolute, reject any ".." traversal, then
# match the ".mico/plans/", ".mico/reports/", or ".claude/projects/*/memory/"
# path SEGMENT, the ".md" suffix, or (for "scratchpad/") the segment plus a
# check that the path is under "$TMPDIR", "/tmp/", "/private/tmp/",
# "/var/folders/", or "/private/var/folders/". We match segments rather than
# anchoring most exemptions to "$cwd" because the orchestrator's cwd is not
# always the project root (e.g. a subdir), which used to false-block legitimate
# plan edits; the scratchpad arm is anchored instead to the system temp root
# (not "$cwd") since that is where the session scratchpad actually lives,
# regardless of cwd. The threat model is the model drifting from plan-only
# discipline, not a hostile attacker, so pure-string normalization (no
# filesystem access, works for not-yet-created files) is enough.
#
# Wired up by bin/mico via `--settings` inline JSON, matcher
# "Edit|Write|NotebookEdit". exit 0 = allow, exit 2 = block (message on stderr).

input=$(cat)

if command -v jq >/dev/null 2>&1; then
  if printf '%s' "$input" | jq -e 'has("agent_id")' >/dev/null 2>&1; then
    exit 0   # subagent -> allow
  fi

  # Main agent: allow only plan docs under "$cwd/.mico/plans/".
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
  if [ -n "$cwd" ] && [ -n "$file_path" ]; then
    # Make absolute (relative paths are resolved against cwd).
    case "$file_path" in
      /*) abs="$file_path" ;;
      *)  abs="$cwd/$file_path" ;;
    esac
    # Reject any ".." traversal (lexical — no filesystem access needed).
    case "$abs" in
      */../*|*/..) ;;   # contains a ".." segment -> fall through to block
      *)
        case "$abs" in
          */.mico/plans/*) exit 0 ;;                # plan doc -> allow
          */.mico/reports/*) exit 0 ;;              # report deliverable -> allow
          */.claude/projects/*/memory/*) exit 0 ;;  # memory doc -> allow
          *.md) exit 0 ;;                            # any markdown -> allow
          */scratchpad/*)
            # Allow only when under the system temp root (where the Claude
            # Code session scratchpad actually lives); any other
            # "scratchpad/" segment (in-project or elsewhere) stays blocked.
            scratchpad_allow=0
            if [ -n "$TMPDIR" ]; then
              tmpdir_norm="${TMPDIR%/}"
              # Guard against TMPDIR being "/" (stripped to ""), a relative
              # path, or otherwise not a real absolute directory: an empty
              # tmpdir_norm would turn the pattern below into "/*", which
              # matches every absolute path and fails the guard open.
              case "$tmpdir_norm" in
                /?*)
                  case "$abs" in
                    "$tmpdir_norm"/*) scratchpad_allow=1 ;;
                  esac
                  ;;
              esac
            fi
            case "$abs" in
              /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*)
                scratchpad_allow=1 ;;
            esac
            [ "$scratchpad_allow" = 1 ] && exit 0
            ;;
        esac
        ;;
    esac
  fi
else
  # Fallback without jq: look for a top-level "agent_id" key. Less precise than
  # jq (a file's content containing the literal string "agent_id" could match),
  # but jq is the expected path; this only degrades on jq-less machines.
  if printf '%s' "$input" | grep -q '"agent_id"'; then
    exit 0   # subagent (best-effort) -> allow
  fi
  # No plan/memory-path exemption without jq: parsing cwd/file_path reliably needs jq,
  # so we degrade to "block" (the safe default) rather than risk a sloppy match.
fi

echo "mico: orchestrator is plan-only — delegate file edits to a subagent (implementer/...). Exceptions: plan docs under .mico/plans/, report deliverables under .mico/reports/, memory docs under ~/.claude/projects/<proj>/memory/, and the session scratchpad are editable directly." >&2
exit 2     # main orchestrator -> block
