#!/usr/bin/env bash
# Runs every test file beside this script and reports the totals.
#
# Usage: bash run.sh [FILE...]
# Exit 0 when every test passed, 1 otherwise. Each test file is sourced
# in its own subshell after lib.sh, so files do not share state; each
# builds its fixtures under a fresh temporary directory that is removed
# afterwards.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  files=()
  for f in "$here"/*.sh; do
    case "$(basename "$f")" in run.sh|lib.sh) ;; *) files+=("$f") ;; esac
  done
fi
total=0; failed=0
for f in "${files[@]}"; do
  out="$(
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    export TMP_ROOT="$tmp"
    . "$here/lib.sh"
    . "$f"
    printf '%d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
  )" || true
  counts="$(printf '%s\n' "$out" | tail -1)"
  n="${counts%% *}"; k="${counts##* }"
  case "$n" in ''|*[!0-9]*) echo "run.sh: $f produced no counts" >&2; failed=$((failed + 1)); continue ;; esac
  total=$((total + n)); failed=$((failed + k))
done
printf '%d tests, %d failed\n' "$total" "$failed"
[ "$failed" -eq 0 ]
