#!/usr/bin/env bash
# claude-code-dialogue — the Claude Code adapter that writes a session's
# dialogue for the summariser subagent (ADR 0008).
#
# Usage:
#   bash claude-code-dialogue.sh <session-id> <project-path> <out-file>
#   bash claude-code-dialogue.sh --help
#
# Locates the session transcript at
#   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<encoded>/<session-id>.jsonl
# where <encoded> is <project-path> with every character outside
# [A-Za-z0-9] replaced by "-". If that file does not exist, it uses the
# single file matching projects/*/<session-id>.jsonl under the same
# root; none, or more than one, is "not found".
#
# Writes <out-file> in the format of references/dialogue.md, with
# "Mode: adapter (claude-code)" on line 2: human messages (including
# those the human sent while a turn was running), assistant prose, and
# questions with their answers, in conversation order. Tool calls and
# output, reasoning, subagent (sidechain) entries and harness-injected
# entries are left out.
#
# Exit codes:
#   0  written
#   1  transcript not found or unreadable, or jq missing; nothing is
#      written to <out-file>, so the caller falls back
#   2  usage error
#
# The transcript format is internal to Claude Code and undocumented, and
# may change between versions. The fixtures were modelled on
# "2.1.296 (Claude Code)".
set -u
usage() { sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
die() { echo "claude-code-dialogue: $2" >&2; exit "$1"; }

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -eq 3 ] || die 2 "usage: claude-code-dialogue <session-id> <project-path> <out-file>"
id="$1" project="$2" out="$3"
command -v jq >/dev/null 2>&1 || die 1 "jq is not installed"

root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
encoded="$(printf '%s' "$project" | sed 's/[^A-Za-z0-9]/-/g')"
transcript="$root/$encoded/$id.jsonl"
if [ ! -f "$transcript" ]; then
  matches=()
  for f in "$root"/*/"$id.jsonl"; do [ -f "$f" ] && matches+=("$f"); done
  [ ${#matches[@]} -eq 1 ] || die 1 "transcript for session $id not found"
  transcript="${matches[0]}"
fi
[ -r "$transcript" ] || die 1 "transcript $transcript is not readable"

# The filter keeps, in order: the human's messages (typed, or queued
# while a turn ran), assistant prose, AskUserQuestion questions and
# their answers. It drops sidechain and isMeta entries, user text the
# harness injected (it starts with "<"), tool calls and other tool
# results, reasoning, and every other entry type.
filter='
  ([.[] | select(.type == "assistant" and .isSidechain != true)
        | .message.content[]? | select(.type == "tool_use" and .name == "AskUserQuestion") | .id]) as $qids
  | def text_of: if type == "string" then . else (map(.text? // "") | join("")) end;
  .[] | select(.isSidechain != true and .isMeta != true)
  | if .type == "user" then
      (.message.content
       | if type == "string" then (select(startswith("<") | not) | {h: "Human", t: .})
         else .[]
           | ((select(.type == "text") | .text | select(startswith("<") | not) | {h: "Human", t: .}),
              (select(.type == "tool_result") | select(.tool_use_id as $i | any($qids[]; . == $i))
               | {h: "Answer", t: (.content | text_of)}))
         end)
    elif .type == "assistant" then
      (.message.content[]?
       | ((select(.type == "text") | {h: "Assistant", t: .text}),
          (select(.type == "tool_use" and .name == "AskUserQuestion")
           | {h: "Question", t: (.input.questions
               | map(.question + "\n" + (.options | map("- " + .label + ": " + .description) | join("\n")))
               | join("\n\n"))})))
    elif .type == "attachment" and .attachment.type == "queued_command" and .attachment.origin.kind == "human" then
      (.attachment.prompt | text_of | select(startswith("<") | not) | {h: "Human", t: .})
    else empty end
  | "\n### \(.h)\n\n\(.t)"'

tmp="$(mktemp "${TMPDIR:-/tmp}/claude-code-dialogue.XXXXXX")" || die 1 "cannot create a temporary file"
trap 'rm -f "$tmp"' EXIT
{ printf '# Dialogue\nMode: adapter (claude-code)\n'
  jq -rs "$filter" "$transcript"
} >"$tmp" 2>/dev/null || die 1 "transcript $transcript could not be read"
mv "$tmp" "$out" || die 1 "cannot write $out"
trap - EXIT
