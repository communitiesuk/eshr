#!/usr/bin/env bash
# `render-requirements` — the README requirements render. Sourced by run.sh
# after lib.sh.
#
# Contract: one Markdown bullet per REQUIRED and DESIRABLE manifest item,
# carrying the item's fix command verbatim where it has one and its install
# guidance where it does not; the reported opt-in subsection with the exact
# line `Bash(gh pr merge *)`; and no git-workflow model-floor bullet.

# The render script and the manifest it reads, resolved from this test
# file's directory. render needs no git repo or sandbox — it only reads
# the manifest — so each test just runs it and inspects stdout.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="$_dir/render-requirements.sh"
RMANIFEST="$_dir/../manifest.json"

render() {
  OUT_STATUS=0
  OUT="$(bash "$RENDER" "$@" 2>"$TMP_ROOT/stderr")" || OUT_STATUS=$?
}

t "1. render succeeds and exits 0"
render
assert_eq 0 "$OUT_STATUS"

t "2. a bullet for every REQUIRED and DESIRABLE item, carrying its label"
render
assert_eq 0 "$OUT_STATUS"
while IFS= read -r label; do
  assert_contains "$OUT" "$label" "missing bullet for item labelled [$label]"
done < <(jq -r '(.required[], .desirable[]) | .label' "$RMANIFEST")

t "3. each item with a fix command renders that command verbatim"
render
assert_eq 0 "$OUT_STATUS"
while IFS= read -r cmd; do
  assert_contains "$OUT" "$cmd" "missing fix command [$cmd]"
done < <(jq -r '(.required[], .desirable[]) | select(.fix_command) | .fix_command' "$RMANIFEST")

t "4. the host-CLI item (guidance, no command) renders its install guidance"
render
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "install the host CLI, e.g. https://cli.github.com"

t "5. the reported subsection prints the exact opt-in line verbatim"
render
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "Bash(gh pr merge *)"
assert_contains "$OUT" "Letting the agent land its own work"

t "6. no git-workflow model-floor bullet is emitted"
render
assert_eq 0 "$OUT_STATUS"
assert_not_contains "$OUT" "model floor"
assert_not_contains "$OUT" "capable enough model"
