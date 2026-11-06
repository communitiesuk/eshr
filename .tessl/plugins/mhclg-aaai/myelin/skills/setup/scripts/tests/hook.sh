#!/usr/bin/env bash
# `check --hook` — the SessionStart path. Sourced by run.sh after lib.sh.
#
# Contract: silent when every REQUIRED and DESIRABLE check passes; on any
# failure, surfaces REQUIRED failures with their fix and DESIRABLE failures
# as a nudge, and reports the opt-in line; ALWAYS exits 0, never blocking.

t "1. a healthy repo is silent in --hook mode and exits 0"
newrepo
add_remote
fake_gh '{"allow_squash_merge":false,"allow_rebase_merge":false}'
run_check --hook
assert_eq 0 "$OUT_STATUS"
assert_eq "" "$OUT" "hook mode must be silent when everything passes"

t "2. no resolvable trunk fails the trunk REQUIRED check with its fix command"
newrepo_notrunk
add_remote
fake_gh '{"allow_squash_merge":false,"allow_rebase_merge":false}'
run_check --hook
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "resolvable trunk"
assert_contains "$OUT" "git remote set-head origin -a"

t "3. a remote but no gh fails the host-CLI REQUIRED check with its install guidance"
newrepo
add_remote
no_gh
run_check --hook
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "host CLI"
assert_contains "$OUT" "https://cli.github.com"

t "4. a host allowing squash/rebase fails the DESIRABLE check with its fix command"
newrepo
add_remote
fake_gh '{"allow_squash_merge":true,"allow_rebase_merge":false}'
run_check --hook
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "merge commits only"
assert_contains "$OUT" "gh api -X PATCH repos/{owner}/{repo}"

t "5. --hook exits 0 even when several REQUIRED checks fail"
newrepo_notrunk
add_remote
no_gh
run_check --hook
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "resolvable trunk"
assert_contains "$OUT" "host CLI"
