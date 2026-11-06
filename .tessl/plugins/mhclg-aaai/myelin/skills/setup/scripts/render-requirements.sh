#!/usr/bin/env bash
# render-requirements — emit the manifest-owned Markdown for the README
# Requirements section.
#
# Read-only. It reads skills/setup/manifest.json (resolved relative to
# this script's own directory, so it runs correctly when invoked as
# ${TESSL_PLUGIN_DIR}/skills/setup/scripts/render-requirements.sh) and prints
# the Markdown the manifest owns: one bullet per REQUIRED and DESIRABLE
# item, plus the reported `gh pr merge` opt-in subsection. It writes
# nothing and changes nothing.
#
# Usage:
#   bash render-requirements.sh      print the Markdown to stdout
#   bash render-requirements.sh --help
#
# Behaviour
#   Each REQUIRED and DESIRABLE manifest item becomes one Markdown bullet:
#   its label in bold, then its prose, then its fix — the item's
#   fix_command where it carries one (rendered verbatim in backticks),
#   otherwise its fix_guidance. The reported item is rendered as the
#   "Letting the agent land its own work" subsection, printing its opt-in
#   line verbatim (`Bash(gh pr merge *)`) in a fenced block and its note.
#
#   The git-workflow model floor is NOT rendered: it is owned by that
#   skill's compatibility frontmatter and serviced by the release-time
#   README read (ADR 0013, ADR 0005 gate 4), not by the manifest. This
#   script emits only what the manifest owns.
#
# Exit codes
#   0  on success
#   1  the manifest could not be found
#
# Depends on jq.

set -u

_src="${BASH_SOURCE[0]}"
_dir="${_src%/*}"
[ "$_dir" = "$_src" ] && _dir="."
MANIFEST="$_dir/../manifest.json"

usage() { sed -n '2,/^$/p' "$_src" 2>/dev/null | sed 's/^# \{0,1\}//'; }

# Emit the items of manifest group $1 (required|desirable) as Markdown
# bullets: label in bold, then prose, then the fix — the fix_command in
# backticks where the item carries one, otherwise the fix_guidance.
emit_bullets() {
  jq -r --arg g "$1" '
    .[$g][] |
    "- **" + .label + ".** " + .prose +
    ( if (.fix_command // "") != "" then " Fix: `" + .fix_command + "`."
      elif (.fix_guidance // "") != "" then " To set it up: " + .fix_guidance + "."
      else "" end )
  ' "$MANIFEST"
}

# Emit the reported opt-in item as the "Letting the agent land its own
# work" subsection: its prose, then its opt-in line verbatim in a fenced
# block, then its note. The line is printed, never checked and never set.
emit_reported() {
  local prose line note
  prose="$(jq -r '.reported[0].prose' "$MANIFEST")"
  line="$(jq -r '.reported[0].opt_in_line' "$MANIFEST")"
  note="$(jq -r '.reported[0].note' "$MANIFEST")"
  printf '### Letting the agent land its own work\n\n'
  printf '%s\n\n' "$prose"
  printf '```\n%s\n```\n\n' "$line"
  printf '%s\n' "$note"
}

main() {
  case "${1:-}" in
    -h|--help) usage; return 0 ;;
    "") ;;
    *) printf 'render-requirements: unknown argument: %s\n' "$1" >&2; return 1 ;;
  esac

  if [ ! -f "$MANIFEST" ]; then
    printf 'render-requirements: manifest not found at %s\n' "$MANIFEST" >&2
    return 1
  fi

  printf '## Requirements\n\n'
  printf 'Before you run myelin in a repository, it needs:\n\n'
  emit_bullets required

  printf '\nAnd it works best when:\n\n'
  emit_bullets desirable

  printf '\n'
  emit_reported
  return 0
}

main "$@"
