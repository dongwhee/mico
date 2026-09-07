#!/usr/bin/env bash
#
# git-guard.sh — PreToolUse hook (matcher: Bash) that enforces the git-safety
# rules in the user's global CLAUDE.md deterministically instead of advisorily.
#
# Two classes of command:
#   deny  — bulk staging: `git add -A`, `git add --all`, `git add .`,
#           `git commit -a`. These are never acceptable (stage by explicit
#           path), so the hook denies them outright with a message the model
#           can act on.
#   ask   — hard-to-undo operations: `git reset --hard`, `git push --force`/`-f`,
#           `git clean -f`, `git branch -D`, `git stash drop|clear`. These need
#           the user's explicit approval, so the hook returns a PreToolUse
#           "ask" decision. In an interactive session that shows a permission
#           prompt even under auto mode; in a headless (-p) session, where
#           nobody can answer, it is refused.
#
# Everything else exits 0 (allow). Applies to the main agent and subagents
# alike — the rule is about the repository, not about who is typing.
#
# Installed into ~/.claude/settings.json by `mico install` (hooks.PreToolUse,
# matcher "Bash") and removed by `mico uninstall`. Needs jq; without it the
# hook exits 0 so a jq-less machine is merely unguarded, never broken.

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[ "$tool" = "Bash" ] || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0

# Reduce the command to the git invocations that actually run: drop quoted
# strings (a commit message may legitimately contain "-a" or "git add -A"),
# split on command separators, and keep only segments that START with `git`.
# "echo git add -A" is therefore not a git command; "cd repo && git add -A" is.
segments=$(printf '%s' "$cmd" \
  | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g" \
  | sed -E 's/(&&|\|\||;|\|)/\n/g' \
  | sed -E 's/^[[:space:]]*(\$?\()*[[:space:]]*//' \
  | grep -E '^git[[:space:]]')
[ -n "$segments" ] || exit 0

# ---- deny: bulk staging ------------------------------------------------------
deny_pat='^git[[:space:]]+add([[:space:]]+-[A-Za-z]*A[A-Za-z]*|[[:space:]]+--all|([[:space:]]+-[^[:space:]]+)*[[:space:]]+\.([[:space:]]|$))'
deny_pat="$deny_pat"'|^git[[:space:]]+commit([[:space:]]+[^[:space:]]+)*[[:space:]]+(-[A-Za-z]*a[A-Za-z]*|--all)([[:space:]]|$)'
if printf '%s\n' "$segments" | grep -Eq "$deny_pat"; then
  echo "git-guard: bulk staging is not allowed (git add -A / --all / ., git commit -a). Stage only the files this task changed, by explicit path, and review git status and the staged diff first." >&2
  exit 2
fi

# ---- ask: hard-to-undo --------------------------------------------------------
ask_pat='^git[[:space:]]+reset([[:space:]]+[^[:space:]]+)*[[:space:]]+--hard'
ask_pat="$ask_pat"'|^git[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+(-[A-Za-z]*f[A-Za-z]*|--force([[:space:]]|$|=)|--force-with-lease)'
ask_pat="$ask_pat"'|^git[[:space:]]+clean([[:space:]]+[^[:space:]]+)*[[:space:]]+-[A-Za-z]*f'
ask_pat="$ask_pat"'|^git[[:space:]]+branch([[:space:]]+[^[:space:]]+)*[[:space:]]+(-[A-Za-z]*D[A-Za-z]*|--delete[[:space:]]+--force|--force[[:space:]]+--delete)'
ask_pat="$ask_pat"'|^git[[:space:]]+stash[[:space:]]+(drop|clear)'
if printf '%s\n' "$segments" | grep -Eq "$ask_pat"; then
  jq -n -c --arg cmd "$cmd" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: ("git-guard: hard-to-undo git operation needs your explicit approval: " + $cmd)
    }
  }'
  exit 0
fi

exit 0
