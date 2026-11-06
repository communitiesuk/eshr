#!/usr/bin/env bash
# `history closed-paths <topic>` — the recall-biased prune and candidate
# extraction. Sourced by run.sh after lib.sh.
#
# Output contract: a `closed-paths:` line, then one record per candidate
# — `path:`, `source:` (alternatives|revises) and `reason:` — grouped by
# the ADR path. The script prunes and extracts only: it never dedupes,
# drops or judges relevance (that is the skill's one model step), so when
# an ADR has both an Alternatives bullet and a Revises body for one
# reversal, both are printed.

adr() {  # adr PATH TITLE DECISION [ALTERNATIVES-BLOCK]
  local path="$1" title="$2" decision="$3" alts="${4:-}"
  mkdir -p "$(dirname "$path")"
  {
    printf -- '---\ntitle: %s\ndate: 2026-05-02\n---\n\n# %s\n\n' "$title" "$title"
    printf '## Decision\n\n%s\n\n' "$decision"
    if [ -n "$alts" ]; then printf '## Alternatives considered\n\n%s\n\n' "$alts"; fi
    printf '## Consequences\n\nSome consequence.\n'
  } > "$path"
}

t "1. a never-adopted path is extracted from an Alternatives bullet, sourced alternatives"
newrepo
adr docs/adr/0001-rate.md "How is the request rate limited?" \
  "A token bucket." \
  "- **A fixed-window counter.** Rejected: it doubles the effective rate at a window boundary."
gc "Add ADR 0001"
history closed-paths "rate limiting"
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "docs/adr/0001-rate.md"
assert_contains "$OUT" "source: alternatives"
assert_contains "$OUT" "fixed-window counter"

t "2. an adopted-then-reversed path is extracted from a Revises body when the ADR does not restate it"
newrepo
adr docs/adr/0002-store.md "Where is the rate-limit counter stored?" "In process memory." ""
gc "Add ADR 0002"
adr docs/adr/0002-store.md "Where is the rate-limit counter stored?" "In Redis, shared across nodes." ""
gc "Revise ADR 0002 to Redis" "The in-process counter was per node and was reversed to Redis.

Revises: docs/adr/0002-store.md"
history closed-paths "rate limiting"
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "docs/adr/0002-store.md"
assert_contains "$OUT" "source: revises"
assert_contains "$OUT" "per node"

t "3. a path with both sources prints both candidates, grouped, with neither suppressed"
newrepo
adr docs/adr/0003-over.md "What happens when a client exceeds its rate limit?" "Drop silently." ""
gc "Add ADR 0003"
adr docs/adr/0003-over.md "What happens when a client exceeds its rate limit?" "Return HTTP 429." \
  "- **Silently dropping the over-limit request.** Tried first, then reversed: clients retried blindly and worsened the overload."
gc "Revise ADR 0003 to 429" "Silently dropping was reversed because clients retried blindly.

Revises: docs/adr/0003-over.md"
history closed-paths "rate limiting"
assert_eq 0 "$OUT_STATUS"
assert_contains "$OUT" "source: alternatives"
assert_contains "$OUT" "source: revises"
assert_contains "$OUT" "Silently dropping"
assert_contains "$OUT" "retried blindly"
# Grouped under one path: the path appears in exactly two records.
assert_eq 2 "$(count_occurrences "$OUT" "docs/adr/0003-over.md")"

t "4. recall-biased prune: an on-topic bullet without the keyword survives; an off-topic ADR is absent"
newrepo
adr docs/adr/0004-rate.md "How is the request rate limited under load?" "A token bucket." \
  "- **A leaky bucket.** Rejected: it smooths away bursts that clients depend on."
adr docs/adr/0005-config.md "How is configuration loaded?" "Parsed once at start-up." \
  "- **Reading environment variables at the point of use.** Rejected: behaviour becomes timing-dependent."
gc "Add ADRs 0004 and 0005"
history closed-paths "rate limiting"
assert_eq 0 "$OUT_STATUS"
# The leaky-bucket bullet has no "rate"/"limit" keyword but its ADR's title does, so it survives.
assert_contains "$OUT" "leaky bucket"
# The off-topic ADR and its bullet are pruned out.
assert_not_contains "$OUT" "0005-config"
assert_not_contains "$OUT" "point of use"
