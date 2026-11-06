# autodefer: the blast-radius auto-defer step (ADR 0011, plan 0021) added
# to cmd_land's new 2a, run inside the same Revises guard as the
# verdict-completeness gate (now 2b) and strictly before it.
#
# No test here needs a remote: every Revises-branch scenario is decided
# (exit 3) or refused before the push step, so every fixture is
# local-only and the non-decision scenario (3) merges with host=none.
#
# Covers plan 0021's Step 2 list (1-9), in order, except scenario 4 runs
# immediately after scenario 1 (it continues scenario 1's own fixture) and
# scenario 8 runs after scenario 5 (it continues scenario 5's fixture, since
# scenario 4 has by then moved scenario 1's trunk).

R="$TMP_ROOT/autodefer"
HIST="$(cd "$(dirname "$SCRIPT")/../../history/scripts" && pwd)/history.sh"
land() { local d="$1"; shift; (cd "$d" && bash "$SCRIPT" land "$@" 2>&1); }

# trailer_values DIR RANGE KEY — every value of trailer KEY over RANGE in
# DIR, one per line, blanks dropped.
trailer_values() { (cd "$1" && git log --format="%(trailers:key=$3,valueonly)" "$2" | sed '/^$/d'); }

# two_downstream_revision DIR — on an already-built fixture rooted at DIR
# (trunk dev, HEAD on dev, docs/adr/0001-one.md already present): begin
# docs/adr/0001-one.md, commit two durable in-tree downstreams
# (plans/9001-downstream.md, plans/9002-other.md, both
# Derives-From: docs/adr/0001-one.md), then the revising commit carrying
# Revises: docs/adr/0001-one.md and any trailer lines held in $VERDICT (an
# embedded-newline string for more than one). begin is in-place on a clean
# trunk, so the echoed wd is the repository root. Echoes wd.
two_downstream_revision() {
  local dir="$1"
  local out wd
  out="$(cd "$dir" && bash "$SCRIPT" begin docs/adr/0001-one.md 2>&1)" || { echo "$out"; return 2; }
  wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  ( cd "$wd" \
    && mkdir -p plans && printf -- '---\ntitle: d1\n---\n' > plans/9001-downstream.md \
    && g add plans/9001-downstream.md \
    && g commit -q -m "$(printf 'Add downstream 1\n\nDerives-From: docs/adr/0001-one.md\n')" \
    && printf -- '---\ntitle: d2\n---\n' > plans/9002-other.md \
    && g add plans/9002-other.md \
    && g commit -q -m "$(printf 'Add downstream 2\n\nDerives-From: docs/adr/0001-one.md\n')" \
    && printf 'changed\n' >> docs/adr/0001-one.md && g add -A \
    && g commit -q -m "$(printf 'Revise\n\nRevises: docs/adr/0001-one.md\n'; [ -n "${VERDICT:-}" ] && printf '%s\n' "$VERDICT")" )
  echo "$wd"
}

# revision2 DIR [fixture options...] — fixture DIR, then
# two_downstream_revision on it. See plan 0021 Step 2 scenario naming.
revision2() {
  local dir="$1"; shift
  fixture "$dir" --trunk dev "$@" >/dev/null || return 2
  two_downstream_revision "$dir"
}

# base_defer DIR ORIGIN — mirrors discharge.sh's base(): a repo on dev
# with one outstanding, not-yet-due deferral already committed on trunk,
# D = plans/9002-other.md, origin ORIGIN. The condition text is free-form
# and irrelevant here: the auto-defer step's exclusion reads only D and
# origin, never the condition.
base_defer() {
  local dir="$1" origin="$2"
  fixture "$dir" --trunk dev >/dev/null || return 2
  (cd "$dir" && g commit -q --allow-empty -m "$(printf 'Defer %s\n\nDefers: %s %s until 9000 revises\n' plans/9002-other.md plans/9002-other.md "$origin")")
}

t "1. partial reconciliation: the untouched downstream is auto-deferred, the reconciled one keeps only its explicit verdict"
  wd="$(VERDICT="Reconciles: plans/9001-downstream.md" revision2 "$R/t1")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  defers="$(trailer_values "$R/t1" dev..adr-0001-one Defers)"
  assert_contains "$defers" "plans/9002-other.md docs/adr/0001-one.md until a plan derives from it"
  case "$defers" in *"plans/9001-downstream.md "*) fail "the explicit Reconciles verdict for 9001 was overwritten with an auto Defers: $defers" ;; esac
  reconciles="$(trailer_values "$R/t1" dev..adr-0001-one Reconciles)"
  assert_contains "$reconciles" "plans/9001-downstream.md"

t "2. full explicit coverage: no auto-defer commit is made"
  wd="$(VERDICT=$'Confirms: plans/9001-downstream.md\nConfirms: plans/9002-other.md' revision2 "$R/t2")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$(cd "$R/t2" && git log --format=%s dev..adr-0001-one)" in
    *"Auto-defer the untouched blast radius"*) fail "an auto-defer commit was made despite full explicit coverage: $out" ;;
  esac

t "3. non-Revises branch: unaffected, no Auto-defer commit reaches the trunk"
  fixture "$R/t3" --trunk dev >/dev/null
  out="$(cd "$R/t3" && bash "$SCRIPT" begin docs/discovery/0002-x.md 2>&1)"
  wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  ( cd "$wd" && mkdir -p docs/discovery && printf -- '---\ntitle: x\n---\n' > docs/discovery/0002-x.md && g add -A \
    && g commit -q -m "$(printf 'Add note\n\nDerives-From: docs/discovery/0001-note.md\n')" )
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  case "$(cd "$R/t3" && git log --format=%s dev)" in
    *"Auto-defer the untouched blast radius"*) fail "an auto-defer commit reached the trunk on a non-Revises branch: $out" ;;
  esac

t "4. the auto-deferred remainder is outstanding once the branch reaches the trunk"
  (cd "$R/t1" && g switch -q dev && g merge -q --ff-only adr-0001-one)
  out="$(cd "$R/t1" && bash "$HIST" outstanding-deferrals)"
  assert_contains "$out" "D: plans/9002-other.md"
  assert_contains "$out" "origin: docs/adr/0001-one.md"
  assert_contains "$out" "due: false"

t "5. two revised ADRs: each auto-defers its own downstream, never the other's"
  fixture "$R/t5" --trunk dev >/dev/null
  (cd "$R/t5" && printf -- '---\ntitle: three\n---\n' > docs/adr/0003-three.md && g add docs/adr/0003-three.md && g commit -q -m "fixture: a second ADR")
  out="$(cd "$R/t5" && bash "$SCRIPT" begin docs/adr/0001-one.md 2>&1)"; wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  ( cd "$wd" && mkdir -p plans \
    && printf -- '---\ntitle: d1\n---\n' > plans/9001-downstream.md && g add plans/9001-downstream.md && g commit -q -m "$(printf 'Add d1\n\nDerives-From: docs/adr/0001-one.md\n')" \
    && printf -- '---\ntitle: d2\n---\n' > plans/9002-two.md && g add plans/9002-two.md && g commit -q -m "$(printf 'Add d2\n\nDerives-From: docs/adr/0003-three.md\n')" \
    && printf 'c1\n' >> docs/adr/0001-one.md && printf 'c3\n' >> docs/adr/0003-three.md && g add -A \
    && g commit -q -m "$(printf 'Revise both\n\nRevises: docs/adr/0001-one.md\nRevises: docs/adr/0003-three.md\n')" )
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  defers="$(trailer_values "$R/t5" dev..adr-0001-one Defers)"
  assert_contains "$defers" "plans/9001-downstream.md docs/adr/0001-one.md until a plan derives from it"
  assert_contains "$defers" "plans/9002-two.md docs/adr/0003-three.md until a plan derives from it"
  case "$defers" in *"plans/9001-downstream.md docs/adr/0003-three.md"*) fail "9001 cited against the wrong origin: $defers" ;; esac
  case "$defers" in *"plans/9002-two.md docs/adr/0001-one.md"*) fail "9002 cited against the wrong origin: $defers" ;; esac

t "6. the gate passes on auto-defer alone: zero explicit verdicts still exits 3, not 2"
  wd="$(revision2 "$R/t6")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the verdict-completeness gate still refused with auto-defer having run: $out" ;; esac

t "7. the remainder excludes a downstream this branch already owes a discharge for"
  # plans/9002-other.md is excluded from auto-defer (its outstanding
  # deferral's origin, docs/adr/0001-one.md, is in this branch's own
  # trigger pool via Revises), so it reaches 2b with no verdict at all
  # and 2b's own backstop refusal is what names it — 2c, which would
  # reject a fresh Defers: there as an invalid re-defer, never runs.
  base_defer "$R/t7" docs/adr/0001-one.md
  wd="$(two_downstream_revision "$R/t7")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "plans/9002-other.md"
  assert_contains "$out" "does not account for every durable downstream"
  case "$out" in *plans/9001-downstream.md*) fail "9001 was auto-deferred and must not be named by the gate: $out" ;; esac
  auto_subjects="$(cd "$R/t7" && git log --format=%s dev..adr-0001-one | grep -F 'Auto-defer the untouched blast radius' || true)"
  if [ -n "$auto_subjects" ]; then
    defers="$(trailer_values "$R/t7" dev..adr-0001-one Defers | awk '{print $1}')"
    case "$defers" in *"plans/9002-other.md"*) fail "the excluded downstream was auto-deferred too: $defers" ;; esac
    assert_contains "$defers" "plans/9001-downstream.md"
  fi

t "8. idempotency: landing a second time makes no second auto-defer commit"
  before="$(cd "$R/t5" && git log --format=%s dev..adr-0001-one | grep -c 'Auto-defer the untouched blast radius')"
  out="$(land "$R/t5"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  after="$(cd "$R/t5" && git log --format=%s dev..adr-0001-one | grep -c 'Auto-defer the untouched blast radius')"
  assert_eq "1" "$before" "expected exactly one auto-defer commit after the first land"
  assert_eq "$before" "$after" "a second land made another auto-defer commit"

t "9. an explicit reviser Defers: is left as-is"
  wd="$(VERDICT="Defers: plans/9001-downstream.md docs/adr/0007-x.md until docs/adr/0007-x.md lands" revision2 "$R/t9")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  defers_9001="$(trailer_values "$R/t9" dev..adr-0001-one Defers | grep '^plans/9001-downstream.md ' || true)"
  count_9001="$(printf '%s\n' "$defers_9001" | sed '/^$/d' | wc -l | tr -d ' ')"
  assert_eq "1" "$count_9001" "a second Defers: trailer was added for 9001: $defers_9001"
  assert_contains "$defers_9001" "plans/9001-downstream.md docs/adr/0007-x.md until docs/adr/0007-x.md lands"
  defers_9002="$(trailer_values "$R/t9" dev..adr-0001-one Defers | grep '^plans/9002-other.md ' || true)"
  assert_contains "$defers_9002" "plans/9002-other.md docs/adr/0001-one.md until a plan derives from it"
