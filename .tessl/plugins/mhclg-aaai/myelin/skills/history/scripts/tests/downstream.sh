#!/usr/bin/env bash
# `history downstream <path>` — the downstream/graph query. Sourced by
# run.sh after lib.sh.
#
# Output contract: a `downstream:` section listing, one per line, every
# path reachable from <path> by following Derives-From trailer values
# forward and transitively (the node at each hop is the deriving commit's
# changed file, not the trailer value); then a `revises:` section listing,
# one line per commit, every commit carrying `Revises: <path>` — <path>'s
# own revision history. The query path is never printed, as a downstream
# node or otherwise.

t "1. a direct Derives-From edge: the ADR's plan is downstream"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit plans/0001-bus.md "Add plan 0001" "Derives-From: docs/adr/0001-bus.md"
history downstream docs/adr/0001-bus.md
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "plans/0001-bus.md"
assert_not_contains "$OUT" "docs/adr/0001-bus.md"

t "2. the two-hop transitive closure: plan and the code the plan produced"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit plans/0001-bus.md "Add plan 0001" "Derives-From: docs/adr/0001-bus.md"
commit src/bus.py "Build the bus" "Derives-From: plans/0001-bus.md"
history downstream docs/adr/0001-bus.md
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "plans/0001-bus.md"
assert_contains "$OUT" "src/bus.py"

t "3. number-reuse decoy: a path sharing a number but not the path is excluded"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit plans/0001-bus.md "Add plan 0001 (bus)" "Derives-From: docs/adr/0001-bus.md"
commit src/bus.py "Build the bus" "Derives-From: plans/0001-bus.md"
commit docs/adr/0002-rel.md "Add ADR 0002"
commit plans/0001-rel.md "Add plan 0001 (releases)" "Derives-From: docs/adr/0002-rel.md"
commit src/rel.py "Build releases" "Derives-From: plans/0001-rel.md"
history downstream docs/adr/0001-bus.md
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "plans/0001-bus.md"
assert_contains "$OUT" "src/bus.py"
assert_not_contains "$OUT" "plans/0001-rel.md"
assert_not_contains "$OUT" "src/rel.py"

t "4. subject-only decoy: a commit naming the path in its subject, no trailer, is excluded"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit plans/0001-bus.md "Add plan 0001" "Derives-From: docs/adr/0001-bus.md"
commit README.md "Document docs/adr/0001-bus.md in the README"
history downstream docs/adr/0001-bus.md
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "plans/0001-bus.md"
assert_not_contains "$OUT" "README.md"

t "5. a self-revision does not make the artefact its own downstream node, and terminates"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit docs/adr/0001-bus.md "Revise ADR 0001 in place" "Revises: docs/adr/0001-bus.md"
history downstream docs/adr/0001-bus.md
assert_eq 0 "$OUT_STATUS"
# Not listed as its own downstream node (the query path appears nowhere):
assert_not_contains "$OUT" "docs/adr/0001-bus.md"
# Its revision history is surfaced in the flat revises section:
assert_contains "$OUT" "revises:"
assert_contains "$OUT" "Revise ADR 0001 in place"

t "6. revises is flat, not transitive: a revision is not followed as a forward edge"
newrepo
commit docs/adr/0001-bus.md "Add ADR 0001"
commit docs/adr/0001-bus.md "Revise ADR 0001 in place" "Revises: docs/adr/0001-bus.md"
commit plans/0001-bus.md "Add plan 0001" "Derives-From: docs/adr/0001-bus.md"
history downstream docs/adr/0001-bus.md
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "plans/0001-bus.md"
# The revision's own changed file (the ADR) must not become a downstream node.
assert_not_contains "$OUT" "docs/adr/0001-bus.md"
