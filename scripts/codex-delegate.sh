#!/usr/bin/env bash
#
# codex-delegate.sh — Delegate a self-contained unit of work to `codex exec`.
#
# Design (per the CC × Codex collaboration findings):
#   - Delegate "code + build + test" (build mode) or "review" as ONE unit.
#   - Codex does the noisy work inside its own sandbox; full stdout goes to a
#     .log file kept in the work dir and is NEVER returned to Claude Code.
#   - Only the agent's FINAL message is written to <verdict> (small: ~0.5-2 KB).
#     Claude Code reads that verdict file and nothing else.
#
# Usage:
#   codex-delegate.sh build  <workdir> <verdict.json> "<prompt>"
#   codex-delegate.sh review <workdir> <verdict.md>   "<prompt>"
#
#   build  -> model_reasoning_effort=high,  verdict is JSON
#   review -> model_reasoning_effort=xhigh, verdict is markdown, read-only intent
#
# Notes:
#   - Approvals + sandbox are bypassed (--dangerously-bypass-approvals-and-sandbox);
#     without it codex exec blocks waiting for interactive approval.
#   - Do NOT use `codex exec review --uncommitted` (auto-includes large untracked
#     build artifacts -> context explosion). Always target files explicitly.

set -uo pipefail

# mico's codex opt-in-only gate. bin/mico exports MICO_CODEX_DISABLED in every
# non-codex --impl mode. The check lives here rather than in a permission rule
# because rules that constrain a command string are unreliable; this one holds
# regardless of how the script was invoked. Unset outside mico, so standalone
# use is unaffected.
if [ -n "${MICO_CODEX_DISABLED:-}" ]; then
  echo "codex-delegate: disabled in this session." >&2
  echo "  mico routes implementation to Claude models unless you ask for codex." >&2
  echo "  Rerun with: mico --impl codex" >&2
  exit 3
fi

usage() {
  # Print the header comment block (everything after the shebang up to the first
  # non-comment line). Deliberately not a hardcoded line range — one of those
  # silently started printing code when a block was inserted below the header.
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

if [ "$#" -lt 4 ]; then
  usage >&2
  exit 2
fi

mode=$1
workdir=$2
verdict=$3
shift 3
prompt="$*"

case "$mode" in
  build)
    effort=${CODEX_DELEGATE_EFFORT:-high}
    suffix=$'\n\n---\nWhen finished, your FINAL message MUST be ONLY a single JSON object and nothing else:\n{"success": <true|false>, "tests_passed": <int>, "tests_failed": <int>, "notes": "<short>"}\nDo not wrap it in code fences. Do not add prose before or after.'
    ;;
  review)
    effort=${CODEX_DELEGATE_EFFORT:-xhigh}
    suffix=$'\n\n---\nReview READ-ONLY: do not modify, create, or delete files.\nEvery checklist item needs `file:line` evidence. No evidence => not PASS.\nSeverity: Critical/Major = BLOCKING, Minor = WARNING.\nYour FINAL message MUST be a markdown report whose FIRST line is exactly\n`VERDICT: PASS` or `VERDICT: FAIL` (FAIL if any BLOCKING item exists).'
    ;;
  *)
    echo "error: unknown mode '$mode' (expected build|review)" >&2
    usage >&2
    exit 2
    ;;
esac

if [ ! -d "$workdir" ]; then
  echo "error: workdir '$workdir' does not exist" >&2
  exit 2
fi

log="${verdict}.log"

codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  -C "$workdir" \
  -c model_reasoning_effort="$effort" \
  -o "$verdict" \
  "${prompt}${suffix}" \
  </dev/null >"$log" 2>&1
status=$?

# Summary line for Claude Code (this is the ONLY thing on stdout).
size="n/a"
[ -f "$verdict" ] && size=$(wc -c <"$verdict" | tr -d ' ')
echo "codex-delegate: mode=$mode effort=$effort exit=$status verdict=$verdict (${size}B) log=$log"
exit "$status"
