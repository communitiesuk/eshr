# discharge: the discharge-due check (ADR 0012, plan 0020) added to
# cmd_land's 2b step, immediately after the ADR 0011 verdict-completeness
# gate (step 1 of this suite).
#
# No test here needs a remote: every scenario is decided before the push
# step, so every fixture is local-only and merges with host=none.
#
# Covers plan 0020's Step 2 list (1-13), in order.

R="$TMP_ROOT/discharge"
land() { local d="$1"; shift; (cd "$d" && bash "$SCRIPT" land "$@" 2>&1); }

D_PATH="plans/9001-downstream.md"
O1_PATH="docs/adr/9000-origin.md"
O2_PATH="docs/adr/9999-o2.md"
D3_PATH="plans/9002-other.md"
O3_PATH="docs/adr/9003-other-origin.md"
COND_DEFAULT="until 9000 revises"

# base DIR [fixture opts...] — a repo on dev with one outstanding,
# not-yet-due deferral already committed on trunk: Defers: D_PATH O1_PATH
# COND_DEFAULT.
base() {
  local dir="$1"; shift
  fixture "$dir" --trunk dev "$@" >/dev/null || return 2
  (cd "$dir" && g commit -q --allow-empty -m "$(printf 'Defer %s\n\nDefers: %s %s %s\n' "$D_PATH" "$D_PATH" "$O1_PATH" "$COND_DEFAULT")")
}

# begin_on DIR PATH — begin DIR's artefact branch for PATH, echo its wd.
begin_on() {
  local dir="$1" path="$2" out wd
  out="$(cd "$dir" && bash "$SCRIPT" begin "$path" 2>&1)" || { echo "$out"; return 2; }
  wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  echo "$wd"
}

# commit_first_derives WD TARGET [PATH] — the branch's required first
# commit, carrying Derives-From: TARGET. Also the Derives-From trigger
# when TARGET is a deferral's origin.
commit_first_derives() {
  local wd="$1" target="$2" path="${3:-docs/discovery/0002-x.md}"
  ( cd "$wd" && mkdir -p "$(dirname "$path")" && printf -- '---\ntitle: x\n---\n' > "$path" && g add -A \
    && g commit -q -m "$(printf 'Add\n\nDerives-From: %s\n' "$target")" )
}

# commit_trailer WD TRAILER-LINE... — an extra allow-empty commit on WD's
# branch carrying the given trailer line(s).
commit_trailer() {
  local wd="$1"; shift
  ( cd "$wd" && g commit -q --allow-empty -m "$(printf 'Note\n\n%s\n' "$*")" )
}

# revision_no_verdict DIR — a Revises branch of docs/adr/0001-one.md with
# an unverdicted, durable in-tree downstream (plan 0017's own fixture
# idiom), on a repo with no deferral recorded at all.
revision_no_verdict() {
  local dir="$1"
  fixture "$dir" --trunk dev >/dev/null || return 2
  local out wd
  out="$(cd "$dir" && bash "$SCRIPT" begin docs/adr/0001-one.md 2>&1)" || { echo "$out"; return 2; }
  wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  ( cd "$wd" && mkdir -p plans && printf -- '---\ntitle: d\n---\n' > plans/9001-downstream.md && g add plans/9001-downstream.md \
    && g commit -q -m "$(printf 'Add downstream\n\nDerives-From: docs/adr/0001-one.md\n')" \
    && printf 'changed\n' >> docs/adr/0001-one.md && g add -A \
    && g commit -q -m "$(printf 'Revise\n\nRevises: docs/adr/0001-one.md\n')" )
  echo "$wd"
}

t "1. visibility: an already-due deferral unrelated to the branch is printed, branch still lands"
  base "$R/t1"
  (cd "$R/t1" && g commit -q --allow-empty -m "$(printf 'Satisfy O1\n\nReconciles: %s\n' "$O1_PATH")")
  wd="$(begin_on "$R/t1" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" docs/discovery/0001-note.md
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  assert_contains "$out" "due-deferrals:"
  assert_contains "$out" "D: $D_PATH"

t "2. hard-stop: a Derives-From trigger with no escape refuses, naming D"
  base "$R/t2"
  wd="$(begin_on "$R/t2" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" "$O1_PATH"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "$D_PATH"
  assert_contains "$out" "no discharge verdict"

t "3. hard-stop: a Revises trigger with no escape refuses, naming D"
  base "$R/t3"
  wd="$(begin_on "$R/t3" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" docs/adr/0001-one.md
  commit_trailer "$wd" "Revises: $O1_PATH"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "$D_PATH"
  assert_contains "$out" "no discharge verdict"

t "4. hard-stop: a Reconciles trigger with no escape refuses, naming D"
  base "$R/t4"
  wd="$(begin_on "$R/t4" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" docs/adr/0001-one.md
  commit_trailer "$wd" "Reconciles: $O1_PATH"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "$D_PATH"
  assert_contains "$out" "no discharge verdict"

t "5. escape: Reconciles: D lands, presence only"
  base "$R/t5"
  wd="$(begin_on "$R/t5" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" "$O1_PATH"
  commit_trailer "$wd" "Reconciles: $D_PATH"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"

t "6. escape: Confirms: D lands, presence only"
  base "$R/t6"
  wd="$(begin_on "$R/t6" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" "$O1_PATH"
  commit_trailer "$wd" "Confirms: $D_PATH"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"

t "7. escape: a fresh Defers: D O2 cond lands when O2 differs from O1 and is unmet"
  base "$R/t7"
  wd="$(begin_on "$R/t7" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" "$O1_PATH"
  commit_trailer "$wd" "Defers: $D_PATH $O2_PATH until 9999 lands"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"

t "8. invalid re-defer (a): re-citing the same origin O1 refuses, naming D"
  base "$R/t8"
  wd="$(begin_on "$R/t8" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" "$O1_PATH"
  commit_trailer "$wd" "Defers: $D_PATH $O1_PATH a new condition"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "$D_PATH"
  assert_contains "$out" "invalid re-defer"

t "9. invalid re-defer (b) via trunk: O2 already met on trunk refuses, naming D"
  base "$R/t9"
  (cd "$R/t9" && g commit -q --allow-empty -m "$(printf 'Satisfy O2\n\nReconciles: %s\n' "$O2_PATH")")
  wd="$(begin_on "$R/t9" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" "$O1_PATH"
  commit_trailer "$wd" "Defers: $D_PATH $O2_PATH until 9999 lands"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "$D_PATH"
  assert_contains "$out" "invalid re-defer"

t "10. invalid re-defer (b) via branch pool: O2 also triggered by this same branch refuses, naming D"
  base "$R/t10"
  wd="$(begin_on "$R/t10" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" "$O1_PATH"
  commit_trailer "$wd" "Derives-From: $O2_PATH"
  commit_trailer "$wd" "Defers: $D_PATH $O2_PATH until 9999 lands"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "$D_PATH"
  assert_contains "$out" "invalid re-defer"

t "11. no regression: the 0011 gate is satisfied by the auto-defer alone when the branch triggers no 0012 deferral (plan 0021)"
  wd="$(revision_no_verdict "$R/t11")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  defers="$(cd "$R/t11" && git log --format='%(trailers:key=Defers,valueonly)' dev..adr-0001-one | sed '/^$/d')"
  assert_contains "$defers" "plans/9001-downstream.md docs/adr/0001-one.md until a plan derives from it"

t "12. not outstanding: a trigger for an already-discharged deferral is not blocked and not listed, while another due deferral still is"
  base "$R/t12"
  (cd "$R/t12" && g commit -q --allow-empty -m "$(printf 'Discharge D\n\nReconciles: %s\n' "$D_PATH")")
  (cd "$R/t12" && g commit -q --allow-empty -m "$(printf 'Defer D3\n\nDefers: %s %s %s\n' "$D3_PATH" "$O3_PATH" "$COND_DEFAULT")")
  (cd "$R/t12" && g commit -q --allow-empty -m "$(printf 'Satisfy O3\n\nReconciles: %s\n' "$O3_PATH")")
  wd="$(begin_on "$R/t12" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" "$O1_PATH"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  assert_contains "$out" "due-deferrals:"
  assert_contains "$out" "D: $D3_PATH"
  case "$out" in *"D: $D_PATH"*) fail "a discharged, non-outstanding deferral was still listed as due: $out" ;; esac

t "13. already-due: a branch re-triggering an already-due origin gets visibility only, still lands"
  base "$R/t13"
  (cd "$R/t13" && g commit -q --allow-empty -m "$(printf 'Satisfy O1\n\nReconciles: %s\n' "$O1_PATH")")
  wd="$(begin_on "$R/t13" docs/discovery/0002-x.md)"
  commit_first_derives "$wd" "$O1_PATH"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  assert_contains "$out" "due-deferrals:"
  assert_contains "$out" "D: $D_PATH"
