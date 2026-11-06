#!/usr/bin/env bash
# Test helpers for the claude-code-dialogue adapter.
#
# Sourced by every test file. Provides:
#   t NAME                       begin a test; increments the count
#   fail MSG                     record a failure of the current test
#   assert_eq EXPECTED ACTUAL [MSG]
#   assert_contains HAYSTACK NEEDLE [MSG]
#   assert_not_contains HAYSTACK NEEDLE [MSG]
#   place FIXTURE PROJECT-DIR [SESSION-ID]
#                                copy fixtures/FIXTURE.jsonl to where the
#                                adapter looks for SESSION-ID's transcript
#                                (default sess-1) for PROJECT-DIR, under
#                                the config root $CFG
#   dialogue [ARGS...]           run the adapter with CLAUDE_CONFIG_DIR=$CFG;
#                                sets OUT_STATUS
#
# Everything is built under $TMP_ROOT, which run.sh creates per file.

set -u

SCRIPT="${SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude-code-dialogue.sh}"
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures"
CFG="$TMP_ROOT/cfg"
TESTS_RUN=0
TESTS_FAILED=0
_CURRENT=""
_FAILED_THIS=0

t() { _CURRENT="$1"; _FAILED_THIS=0; TESTS_RUN=$((TESTS_RUN + 1)); }

fail() {
  if [ "$_FAILED_THIS" -eq 0 ]; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _FAILED_THIS=1
  fi
  printf 'FAIL %s: %s\n' "$_CURRENT" "$1" >&2
}

assert_eq() { if [ "$1" != "$2" ]; then fail "${3:-expected [$1] got [$2]}"; fi; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "${3:-output lacks [$2]}" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "${3:-output has [$2]}" ;; esac; }

encode() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

place() {
  local fx="$1" proj="$2" id="${3:-sess-1}"
  mkdir -p "$CFG/projects/$(encode "$proj")"
  cp "$FIXTURES/$fx.jsonl.txt" "$CFG/projects/$(encode "$proj")/$id.jsonl"
}

dialogue() {
  OUT_STATUS=0
  CLAUDE_CONFIG_DIR="$CFG" bash "$SCRIPT" "$@" >"$TMP_ROOT/stdout" 2>"$TMP_ROOT/stderr" || OUT_STATUS=$?
}
