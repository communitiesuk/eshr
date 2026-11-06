#!/usr/bin/env bash
# `check` (default mode) — the doctor path. Sourced by run.sh after lib.sh.
#
# Contract: a full per-item report — one pass/fail line per REQUIRED and
# DESIRABLE item, with the item's fix on failure — and the reported
# opt-in line printed verbatim, never checked and never acted on.

t "1. a healthy repo reports its requirements and exits 0"
newrepo
add_remote
fake_gh '{"allow_squash_merge":false,"allow_rebase_merge":false}'
run_check
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "git present"
assert_contains "$OUT" "Bash present"
assert_contains "$OUT" "merge commits only"

t "2. the reported opt-in line is printed verbatim and never acted on"
newrepo
add_remote
fake_gh '{"allow_squash_merge":false,"allow_rebase_merge":false}'
run_check
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "Bash(gh pr merge *)"
# The script is read-only: it must never invoke `gh pr merge`.
assert_not_contains "$(cat "$GHLOG")" "pr merge"

t "3. no resolvable trunk fails the trunk check and prints its fix command"
newrepo_notrunk
add_remote
fake_gh '{"allow_squash_merge":false,"allow_rebase_merge":false}'
run_check
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "resolvable trunk"
assert_contains "$OUT" "git remote set-head origin -a"

t "4. a remote but no gh fails the host-CLI check and prints its install guidance"
newrepo
add_remote
no_gh
run_check
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "host CLI"
assert_contains "$OUT" "install the host CLI, e.g. https://cli.github.com"

t "5. a host allowing squash/rebase fails the DESIRABLE check and prints its fix"
newrepo
add_remote
fake_gh '{"allow_squash_merge":true,"allow_rebase_merge":true}'
run_check
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "merge commits only"
assert_contains "$OUT" "gh api -X PATCH repos/{owner}/{repo} -F allow_squash_merge=false -F allow_rebase_merge=false"

t "6. a gated remote-exists check is skipped, not failed, when there is no remote"
newrepo
no_gh
run_check
assert_eq 0 "$OUT_STATUS"
# No remote: the host-CLI requirement must not be reported as a failure.
assert_not_contains "$OUT" "install the host CLI"
