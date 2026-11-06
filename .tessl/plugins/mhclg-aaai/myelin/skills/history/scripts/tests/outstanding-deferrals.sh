#!/usr/bin/env bash
# `history outstanding-deferrals` — the outstanding-deferrals query.
# Sourced by run.sh after lib.sh.
#
# Output contract: one record per outstanding deferral, separated by a
# blank line: `D:`, `origin:`, `condition:` (the raw value after D,
# unmodified, including the origin token), `due: true|false`, and zero or
# more `candidate: <short-hash> <subject>` lines, present only when
# `due: true`. Per D, the latest of `Reconciles: D`, `Confirms: D` or
# `Defers: D <origin> <condition>` seen while walking trunk commits in
# `git log <trunk> --topo-order --reverse` order decides whether D is
# outstanding at all (Mechanism 5); `due` is decided separately, by
# whether any later commit in that same ordering carries `Reconciles:`,
# `Revises:` or `Derives-From:` naming the deferral's own *origin* path
# (Mechanism 6) — a different trailer target than the D-verdicts above.

t "1. no trigger anywhere: not due"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit plans/0001-bus.md "Defer plan 0001 on ADR 0001" \
  "Defers: plans/0001-bus.md docs/adr/0001-bus.md waiting on a decision"
history outstanding-deferrals
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "D: plans/0001-bus.md"
assert_contains "$OUT" "origin: docs/adr/0001-bus.md"
assert_contains "$OUT" "due: false"
assert_not_contains "$OUT" "candidate:"

t "2. a post-deferral trigger: due, with a candidate line"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit plans/0001-bus.md "Defer plan 0001 on ADR 0001" \
  "Defers: plans/0001-bus.md docs/adr/0001-bus.md waiting on a decision"
commit src/bus.py "Build the bus" "Derives-From: docs/adr/0001-bus.md"
history outstanding-deferrals
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "D: plans/0001-bus.md"
assert_contains "$OUT" "due: true"
assert_contains "$OUT" "candidate:"
assert_contains "$OUT" "Build the bus"

t "3. a pre-existing, earlier trigger: not due (ordering, not just presence)"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit src/bus.py "Build the bus" "Derives-From: docs/adr/0001-bus.md"
commit plans/0001-bus.md "Defer plan 0001 on ADR 0001" \
  "Defers: plans/0001-bus.md docs/adr/0001-bus.md waiting on a decision"
history outstanding-deferrals
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "D: plans/0001-bus.md"
assert_contains "$OUT" "due: false"
assert_not_contains "$OUT" "candidate:"

t "4. already discharged by a later Reconciles verdict: excluded entirely"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit plans/0001-bus.md "Defer plan 0001 on ADR 0001" \
  "Defers: plans/0001-bus.md docs/adr/0001-bus.md waiting on a decision"
commit plans/0001-bus.md "Reconcile plan 0001" "Reconciles: plans/0001-bus.md"
history outstanding-deferrals
assert_eq 0 "$OUT_STATUS"
assert_not_contains "$OUT" "D: plans/0001-bus.md"

t "5. multiple candidates: due, both returned"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit plans/0001-bus.md "Defer plan 0001 on ADR 0001" \
  "Defers: plans/0001-bus.md docs/adr/0001-bus.md waiting on a decision"
commit src/bus.py "Build the bus" "Derives-From: docs/adr/0001-bus.md"
commit docs/adr/0001-bus.md "Revise ADR 0001" "Revises: docs/adr/0001-bus.md"
history outstanding-deferrals
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "D: plans/0001-bus.md"
assert_contains "$OUT" "due: true"
assert_eq 2 "$(count_occurrences "$OUT" "candidate:")"
assert_contains "$OUT" "Build the bus"
assert_contains "$OUT" "Revise ADR 0001"

t "6. a re-defer: the second Defers wins, the first is gone entirely"
newrepo
commit docs/adr/0001-first.md "Add ADR 0001 (first)"
commit docs/adr/0002-second.md "Add ADR 0002 (second)"
commit plans/0001-bus.md "Defer plan 0001 on ADR 0001" \
  "Defers: plans/0001-bus.md docs/adr/0001-first.md first condition"
commit plans/0001-bus.md "Re-defer plan 0001 on ADR 0002" \
  "Defers: plans/0001-bus.md docs/adr/0002-second.md second condition"
commit src/bus.py "Build the bus" "Derives-From: docs/adr/0002-second.md"
history outstanding-deferrals
assert_eq 0 "$OUT_STATUS"
assert_eq 1 "$(count_occurrences "$OUT" "D: plans/0001-bus.md")"
assert_contains "$OUT" "origin: docs/adr/0002-second.md"
assert_contains "$OUT" "second condition"
assert_contains "$OUT" "due: true"
assert_contains "$OUT" "Build the bus"
assert_not_contains "$OUT" "docs/adr/0001-first.md"
assert_not_contains "$OUT" "first condition"

t "7. a Reconciles targeting the origin, not D: still outstanding, and due"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit plans/0001-bus.md "Defer plan 0001 on ADR 0001" \
  "Defers: plans/0001-bus.md docs/adr/0001-bus.md waiting on a decision"
commit docs/adr/0001-bus.md "Reconcile ADR 0001 itself" "Reconciles: docs/adr/0001-bus.md"
history outstanding-deferrals
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "D: plans/0001-bus.md"
assert_contains "$OUT" "due: true"
assert_contains "$OUT" "candidate:"
assert_contains "$OUT" "Reconcile ADR 0001 itself"
