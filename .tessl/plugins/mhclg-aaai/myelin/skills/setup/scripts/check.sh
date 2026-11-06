#!/usr/bin/env bash
# check — verify this repository against myelin's requirements manifest.
#
# Read-only. It reads skills/setup/manifest.json (resolved relative to
# this script's own directory, so it runs correctly when invoked as
# ${TESSL_PLUGIN_DIR}/skills/setup/scripts/check.sh) and reports each
# REQUIRED and DESIRABLE requirement as pass or fail. It never changes
# anything in the repository or on the host.
#
# Usage:
#   bash check.sh            full per-item report (the doctor path)
#   bash check.sh --hook     quiet unless something fails (the SessionStart path)
#   bash check.sh --help
#
# Behaviour
#   For every REQUIRED and DESIRABLE manifest item it emits one line:
#   pass, or fail with the item's fix (its fix_command where it carries
#   one, otherwise its fix_guidance). Items gated `"when": "remote-exists"`
#   are evaluated only where this repository has a remote; elsewhere they
#   are skipped, not failed. The `reported` item is never checked or set:
#   its opt-in line is printed verbatim as a user decision.
#
#   Default mode prints the full per-item report.
#
#   --hook mode is silent when every REQUIRED and DESIRABLE check passes.
#   On any failure it surfaces REQUIRED failures prominently and DESIRABLE
#   failures as a nudge, and prints the reported opt-in line. It ALWAYS
#   exits 0 and never blocks a session — the same exit-0/advisory
#   discipline as .claude/hooks/refresh-myelin.sh.
#
# Exit codes
#   0  always (read-only advisory; --hook must never block a session)
#
# Depends on git and jq, and on the host CLI (gh) only to read host
# merge settings; its absence is reported, never fatal.

set -u

# Resolve the manifest relative to this script's own directory, using
# only bash parameter expansion so no external tool (dirname) is needed —
# the script runs under a minimal PATH at hook time and under test.
_src="${BASH_SOURCE[0]}"
_dir="${_src%/*}"
[ "$_dir" = "$_src" ] && _dir="."
MANIFEST="$_dir/../manifest.json"

# Succeed when this repository has at least one git remote.
remote_exists() { [ -n "$(git remote 2>/dev/null)" ]; }

# Succeed when git-workflow can resolve a trunk: a local `dev`, a local
# `develop`, or whatever refs/remotes/origin/HEAD names.
resolvable_trunk_ok() {
  git show-ref --verify --quiet refs/heads/dev && return 0
  git show-ref --verify --quiet refs/heads/develop && return 0
  git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null 2>&1 && return 0
  return 1
}

# Succeed when the host is configured for merge commits only (neither
# squash nor rebase merges allowed). Can't-assess (no remote, no host
# CLI, or no answer) counts as a pass, so the check never nags blindly.
merge_settings_ok() {
  remote_exists || return 0
  command -v gh >/dev/null 2>&1 || return 0
  local json
  json="$(gh api "repos/{owner}/{repo}" 2>/dev/null)" || return 0
  [ -n "$json" ] || return 0
  # Fail only when the host positively allows a squash or rebase merge.
  if printf '%s' "$json" | jq -e '(.allow_squash_merge // false) or (.allow_rebase_merge // false)' >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# Succeed when the manifest item with id $1 passes. $2 is the item's
# `check_command` hint (may be empty). id-specific checks (resolvable
# trunk, merge settings) are dispatched here; everything else runs its
# check_command.
item_passes() {
  local id="$1" check_command="$2"
  case "$id" in
    resolvable-trunk) resolvable_trunk_ok ;;
    merge-settings) merge_settings_ok ;;
    *)
      [ -n "$check_command" ] || return 0
      eval "$check_command" >/dev/null 2>&1
      ;;
  esac
}

# Print the fix for a failed item: $1 fix_command (may be empty), $2
# fix_guidance. The command is preferred where the item carries one.
fix_of() {
  if [ -n "$1" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

# Emit the manifest's items of group $1 (required|desirable) as records
# of six fields joined by \x1f (unit separator): id, label, when,
# check_command, fix_command, fix_guidance. \x1f is non-whitespace, so an
# empty field (a missing `when` or `check_command`) survives `read` with
# IFS=$'\x1f' instead of collapsing and shifting the columns.
_items() {
  jq -r --arg g "$1" '
    .[$g][] |
    [ .id, .label, (.when // ""), (.check_command // ""),
      (.fix_command // ""), (.fix_guidance // "") ] | join("\u001f")
  ' "$MANIFEST"
}

# Print the reported opt-in line and its note, verbatim, as a user
# decision. Never checked, never set.
_reported() {
  jq -r '.reported[] | .opt_in_line, .note' "$MANIFEST"
}

# Evaluate one group: $1 = required|desirable, $2 = array-name prefix
# (REQ|DES). For each evaluated item, append its label to <pfx>_PASS or
# <pfx>_FAIL (+ its fix to <pfx>_FIX). Gated remote-exists items are
# skipped where there is no remote. Appends directly to the prefixed
# arrays — no bulk array copy — so it is safe under set -u on old bash.
_have_remote=""
evaluate_group() {
  local group="$1" pfx="$2" id label when check_command fix_command fix_guidance fix
  while IFS=$'\x1f' read -r id label when check_command fix_command fix_guidance; do
    [ -n "$id" ] || continue
    if [ "$when" = "remote-exists" ] && [ "$_have_remote" != "1" ]; then
      continue
    fi
    if item_passes "$id" "$check_command"; then
      eval "${pfx}_PASS+=(\"\$label\")"
    else
      fix="$(fix_of "$fix_command" "$fix_guidance")"
      eval "${pfx}_FAIL+=(\"\$label\")"
      eval "${pfx}_FIX+=(\"\$fix\")"
    fi
  done < <(_items "$group")
}

# The full per-item report (default mode): every evaluated REQUIRED and
# DESIRABLE item as pass/fail with its fix, then the reported opt-in line.
report_default() {
  local i
  printf 'Setup requirements check\n\n'

  printf 'Required\n'
  for ((i = 0; i < ${#REQ_PASS[@]}; i++)); do printf '  pass  %s\n' "${REQ_PASS[$i]}"; done
  for ((i = 0; i < ${#REQ_FAIL[@]}; i++)); do
    printf '  FAIL  %s\n        fix: %s\n' "${REQ_FAIL[$i]}" "${REQ_FIX[$i]}"
  done

  printf '\nDesirable\n'
  for ((i = 0; i < ${#DES_PASS[@]}; i++)); do printf '  pass  %s\n' "${DES_PASS[$i]}"; done
  for ((i = 0; i < ${#DES_FAIL[@]}; i++)); do
    printf '  FAIL  %s\n        fix: %s\n' "${DES_FAIL[$i]}" "${DES_FIX[$i]}"
  done

  printf '\nReported (a user decision — never checked, never set)\n'
  _reported | while IFS= read -r line; do printf '  %s\n' "$line"; done
}

# The quiet-or-nudge report (--hook mode): silent when nothing failed;
# otherwise REQUIRED failures prominently, DESIRABLE failures as a nudge,
# and the reported opt-in line. Always returns 0.
report_hook() {
  local i
  if [ ${#REQ_FAIL[@]} -eq 0 ] && [ ${#DES_FAIL[@]} -eq 0 ]; then
    return 0
  fi

  if [ ${#REQ_FAIL[@]} -gt 0 ]; then
    printf 'myelin setup — REQUIRED checks failed:\n'
    for ((i = 0; i < ${#REQ_FAIL[@]}; i++)); do
      printf '  - %s\n    fix: %s\n' "${REQ_FAIL[$i]}" "${REQ_FIX[$i]}"
    done
  fi

  if [ ${#DES_FAIL[@]} -gt 0 ]; then
    [ ${#REQ_FAIL[@]} -gt 0 ] && printf '\n'
    printf 'myelin setup — desirable (not blocking):\n'
    for ((i = 0; i < ${#DES_FAIL[@]}; i++)); do
      printf '  - %s\n    fix: %s\n' "${DES_FAIL[$i]}" "${DES_FIX[$i]}"
    done
  fi

  printf '\nReported (a user decision — never checked, never set):\n'
  _reported | while IFS= read -r line; do printf '  %s\n' "$line"; done
  return 0
}

usage() { sed -n '2,/^$/p' "$_src" 2>/dev/null | sed 's/^# \{0,1\}//'; }

main() {
  local mode="default"
  case "${1:-}" in
    -h|--help) usage; return 0 ;;
    --hook) mode="hook" ;;
    "") ;;
    *) printf 'check: unknown argument: %s\n' "$1" >&2; return 0 ;;
  esac

  if [ ! -f "$MANIFEST" ]; then
    [ "$mode" = "hook" ] && return 0
    printf 'check: manifest not found at %s\n' "$MANIFEST" >&2
    return 0
  fi

  remote_exists && _have_remote="1" || _have_remote="0"

  REQ_PASS=(); REQ_FAIL=(); REQ_FIX=()
  DES_PASS=(); DES_FAIL=(); DES_FIX=()
  evaluate_group required REQ
  evaluate_group desirable DES

  if [ "$mode" = "hook" ]; then
    report_hook
  else
    report_default
  fi
  return 0
}

main "$@"
