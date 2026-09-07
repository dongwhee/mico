#!/usr/bin/env bash
#
# intent-turn-probe.sh — Stop hook, OBSERVE MODE ONLY. It never blocks: it
# always exits 0, and it never emits a hook-control verdict. Its only side
# effect is appending a line to a log file when a turn looks like it ended on
# an ANNOUNCED-BUT-UNPERFORMED action ("리뷰를 붙이겠습니다" / "I'll run the
# review" with no tool call following) instead of the action itself. Whether
# this ever flips to blocking is a separate decision, made later, after
# counting false positives on real sessions — Korean polite forms such as
# "확인 부탁드리겠습니다" are EXPECTED to match and are exactly what we are
# counting, not a bug to silence here.
#
# Payload contract (Claude Code 2.1.263, confirmed by probe — see
# .mico/plans/review-loop-termination.md step 1): the Stop payload carries
# "last_assistant_message" as a PLAIN STRING holding the final assistant text
# for the turn. We read the message straight from that field. We deliberately
# never open or parse the transcript path field — arise transcripts run tens
# of MB, and last_assistant_message already gives us the text we need without
# a streaming read or any stop_reason parsing.
#
# "Stop" does not fire for subagents (they fire "SubagentStop", whose payload
# carries "agent_id" instead) — confirmed by the same probe — so no agent
# filtering is needed here, unlike scripts/orchestrator-guard.sh which must
# tell the main agent apart from subagents.
#
# Detection: match the FINAL SENTENCE of last_assistant_message against an
# "intent" pattern (Korean/English future-action phrasing) requiring that it
# contain no "decision marker" (a question mark, a Korean question ending, a
# conditional, or an explicit confirm/approve word) — the idea being that
# "질문/조건이 섞인 문장" is asking or hedging, not just announcing.
#
# "Final sentence" — the definition used here, spelled out because the spec
# leaves it to judgement:
#   1. Take the LAST NON-EMPTY line of the message (a stray trailing blank
#      line must not blank the detector).
#   2. Strip a trailing run of sentence terminators (. ! ?) off the end of
#      that line, if present, remembering what was stripped.
#   3. Within what's left, take the text after the LAST remaining terminator
#      (or the whole remainder, if none) — that's the final sentence's body —
#      then reattach the terminator run stripped in step 2.
# This keeps a single-sentence line ("...겠습니다.") intact as one sentence
# instead of splitting at its own trailing period, while still isolating the
# final sentence out of a line that holds more than one.
#
# Wired up by bin/mico via `--settings` inline JSON, event "Stop".
# Exit codes: always 0. No stdout output on any path — this hook only ever
# observes; it has no verdict to signal.

input=$(cat)

# No jq -> exit 0 silently (no fallback parsing here: unlike the guard hook,
# this one has nothing useful to do without real JSON/regex support).
command -v jq >/dev/null 2>&1 || exit 0

# Pull every field we need out of one jq call, NUL-separated so embedded
# newlines in last_assistant_message can't be confused with a field
# separator. Malformed/empty/non-JSON input -> jq fails -> exit 0, write
# nothing (the "robust to a malformed payload" requirement).
fields=()
while IFS= read -r -d '' field; do
  fields+=("$field")
done < <(printf '%s' "$input" | jq -j '
    (.stop_hook_active // false | tostring) + "\u0000" +
    (.last_assistant_message // "") + "\u0000" +
    (.cwd // "") + "\u0000" +
    (.session_id // "") + "\u0000"
  ' 2>/dev/null) || exit 0

stop_hook_active="${fields[0]:-}"
message="${fields[1]:-}"
cwd="${fields[2]:-}"
session_id="${fields[3]:-}"

# Loop guard: on the re-entry after a block, stop_hook_active flips to true.
# This hook never blocks, but honor the field anyway (exit immediately,
# writing nothing) so it behaves like every other well-behaved Stop hook.
[ "$stop_hook_active" = "true" ] && exit 0

# Nothing to inspect, or nowhere to log to -> exit 0, write nothing.
[ -z "$message" ] && exit 0
[ -z "$cwd" ] && exit 0

# ---- final-sentence extraction (see header comment for the definition) ----

last_line=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    *[![:space:]]*) last_line="$line" ;;   # keep the last non-blank line seen
  esac
done <<<"$message"

[ -z "$last_line" ] && exit 0   # message was entirely blank

# Trim trailing whitespace so a trailing terminator run is found at the true
# end of the line's content.
last_line="${last_line%"${last_line##*[![:space:]]}"}"

# Strip a trailing run of sentence terminators, remembering it.
trailing_punct=""
core="$last_line"
if [[ "$core" =~ ([.!?]+)$ ]]; then
  trailing_punct="${BASH_REMATCH[1]}"
  core="${core%"$trailing_punct"}"
fi

# Text after the LAST remaining terminator in $core (glob, longest-prefix
# removal — matches through the last '.', '!' or '?' still in $core; if none
# remain, the parameter is left unchanged, i.e. the whole of $core).
body="${core##*[.!?]}"
body="${body# }"   # drop one leading space left by a "... . Next sentence" split

final_sentence="${body}${trailing_punct}"

[ -z "$final_sentence" ] && exit 0

# ---- pattern match ----------------------------------------------------------

# Intent: future/about-to-act phrasing, Korean and English.
intent_pattern="겠습니다|할게요|하겠어요|I'll|I will|Let me|Next,? I|Now I"
# Decision marker: a question, a Korean question ending, a conditional, or an
# explicit confirm/approve word — any of these means the turn is asking or
# hedging, not just announcing, so it does not count as a match even if the
# intent pattern also matched.
#
# Word-boundary classes here are [^a-zA-Z]/[a-zA-Z] rather than
# [[:alnum:]]/[^[:alnum:]] on purpose: [[:alnum:]] classifies Korean syllables
# as alphanumeric under a UTF-8 locale (e.g. LANG=en_US.UTF-8) but not under
# LC_ALL=C, which would make the boundary — and therefore whether "confirm"
# embedded next to Korean text counts as a whole word — depend on a locale
# this hook's process doesn't control. Restricting the class to ASCII letters
# keeps the boundary check identical under any locale, while still treating
# "verify"/"modify" (which contain the letters "if" only adjacent to other
# ASCII letters) as non-matches.
#
# The 면(...) alternative also accepts a following comma or common sentence
# punctuation, not just whitespace/end-of-string, so "없으면, ..." still
# counts as a conditional even though the comma sits between 면 and the next
# clause. The ideographic comma (、) and middle dot (·) are pulled out of the
# bracket class into their own alternatives rather than living inside
# [[:space:],.、·)] — a bracket class holding multibyte characters degrades to
# matching their constituent raw bytes under LC_ALL=C, which would make the
# class match any lone byte of E3/80/81 (、) or C2/B7 (·), including bytes
# that only coincidentally overlap a *different* multibyte character — a
# NBSP (C2 A0) shares its leading C2 with ·, so a NBSP's first byte alone
# satisfied the old class. Keeping the bracket class itself ASCII-only and
# moving 、/· to alternations (each matched as one atomic byte sequence, not
# a set of individual bytes) removes that coincidental cross-character
# matching. A literal NBSP (C2 A0) and ideographic space (E3 80 80)
# alternative is added explicitly for the same reason [[:space:]] is not
# enough on its own: under en_US.UTF-8, [[:space:]] already classifies NBSP
# as whitespace, but under LC_ALL=C — a single-byte locale — each is a
# multi-byte sequence that no single-character POSIX class can match, so
# without an explicit byte-sequence alternative here 면+NBSP would match under
# UTF-8 but not under C, the same kind of locale-dependent inconsistency this
# whole fix is about. Other Unicode spaces (U+2003, U+2009) remain
# locale-dependent here; only the ones seen in practice are enumerated.
decision_pattern='\?|까요|면([[:space:],.)]|、|·|'$'\xe3\x80\x80''|'$'\xc2\xa0''|$)|(^|[^a-zA-Z])(if|once|whether|confirm|approve)([^a-zA-Z]|$)'

# The confirm/approve/if/once/whether words above should match regardless of
# case ("Confirm the plan..." / "Once done..."), but nocasematch is scoped to
# just this one test — turning it on for the intent_pattern match too would
# change unrelated matching behavior this task isn't asked to touch. Save and
# restore the prior setting so we don't leak a locale/shopt change to the rest
# of the hook process.
nocasematch_was_set=1
shopt -q nocasematch || nocasematch_was_set=0
shopt -s nocasematch
decision_match=1
[[ "$final_sentence" =~ $decision_pattern ]] || decision_match=0
[ "$nocasematch_was_set" -eq 1 ] || shopt -u nocasematch

if [[ "$final_sentence" =~ $intent_pattern ]] && [ "$decision_match" -eq 0 ]; then
  mkdir -p "$cwd/.mico" 2>/dev/null || exit 0
  logfile="$cwd/.mico/intent-turn-log.jsonl"
  jq -n -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$session_id" \
    --arg sentence "$final_sentence" \
    '{timestamp: $ts, session_id: $sid, final_sentence: $sentence[0:300]}' \
    >>"$logfile" 2>/dev/null
fi

exit 0
