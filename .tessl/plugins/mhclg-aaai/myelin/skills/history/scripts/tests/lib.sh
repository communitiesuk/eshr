#!/usr/bin/env bash
# Test helpers for the history retrieval script.
#
# Sourced by every test file. Provides:
#   t NAME                       begin a test; increments the count
#   fail MSG                     record a failure of the current test
#   assert_eq EXPECTED ACTUAL [MSG]
#   assert_contains HAYSTACK NEEDLE [MSG]
#   assert_not_contains HAYSTACK NEEDLE [MSG]
#   newrepo                      create and cd into a fresh git repository
#                                under $TMP_ROOT, with a local identity
#   commit PATH SUBJECT [BODY]   write a one-line-marker file at PATH (its
#                                content is "<PATH> v<n>", bumped on each
#                                rewrite so edits are real), git add it and
#                                commit with SUBJECT; BODY, if given, is the
#                                full commit body (used to carry trailers)
#   history [ARGS...]            run the history script in the current repo;
#                                sets OUT (stdout) and OUT_STATUS
#
# Everything is built under $TMP_ROOT, which run.sh creates per file.

set -u

SCRIPT="${SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/history.sh}"
TESTS_RUN=0
TESTS_FAILED=0
_CURRENT=""
_FAILED_THIS=0
_REPO_N=0

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

newrepo() {
  _REPO_N=$((_REPO_N + 1))
  local d="$TMP_ROOT/repo-$_REPO_N"
  mkdir -p "$d"
  cd "$d" || return 1
  git init -q .
  git symbolic-ref HEAD refs/heads/dev
  git config --local user.name "History Tests"
  git config --local user.email "tests@history.invalid"
  git config --local commit.gpgsign false
}

commit() {
  local path="$1" subject="$2" body="${3:-}"
  mkdir -p "$(dirname "$path")"
  local n=1
  if [ -f "$path" ]; then n=$(( $(sed -n 's/.* v\([0-9]*\)$/\1/p' "$path" | tail -1) + 1 )); fi
  printf '%s v%d\n' "$path" "$n" > "$path"
  git add "$path"
  if [ -n "$body" ]; then
    printf '%s\n\n%s\n' "$subject" "$body" | git commit -q --cleanup=whitespace -F -
  else
    git commit -q -m "$subject"
  fi
}

# Stage everything in the throwaway repo and commit with SUBJECT and, if
# given, BODY (used to carry a Revises trailer). For closed-paths fixtures
# whose files are written directly rather than through commit().
gc() {
  git add -A
  if [ -n "${2:-}" ]; then
    printf '%s\n\n%s\n' "$1" "$2" | git commit -q --cleanup=whitespace -F -
  else
    git commit -q -m "$1"
  fi
}

history() {
  OUT_STATUS=0
  OUT="$(bash "$SCRIPT" "$@" 2>"$TMP_ROOT/stderr")" || OUT_STATUS=$?
}

# Count non-overlapping occurrences of NEEDLE in HAYSTACK (for grouping
# assertions, e.g. "this path appears in exactly two records").
count_occurrences() {
  printf '%s' "$1" | grep -oF -- "$2" | wc -l | tr -d ' '
}
