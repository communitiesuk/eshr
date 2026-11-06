#!/usr/bin/env bash
# history — the retrieval half of the history skill.
#
# Reads this repository's git history to answer two questions about the
# artefact graph and the record of closed decisions. It reads trailer
# fields and in-tree ADR sections only; it never parses a commit subject
# line as an edge.
#
# Usage:
#   bash history.sh downstream <path>
#   bash history.sh closed-paths <topic>
#   bash history.sh outstanding-deferrals
#   bash history.sh --help
#
# Subcommands
#   closed-paths <topic>
#       Print the closed-path candidates on <topic>, for a model step to
#       judge for relevance and dedupe. First a recall-biased prune: an
#       ADR is on topic when its title or any of its `## Alternatives
#       considered` bullets shares a (lightly stemmed) word with <topic>.
#       The prune is deliberately wider than an exact-keyword match — a
#       false positive costs a discarded read, a false negative silently
#       reopens a closed path. Then, for every on-topic ADR, print one
#       record per candidate: its path, the source (`alternatives` for an
#       Alternatives bullet, `revises` for the body of a commit carrying
#       `Revises: <that ADR>`), and the reason text. Records are grouped
#       by the ADR path they concern. No model runs here and nothing is
#       deduped or dropped: when an ADR has both an Alternatives bullet
#       and a Revises body for the same reversal, both are printed. The
#       relevance judgement and the dedupe are the skill's one model step.
#   downstream <path>
#       Print what derives from <path>, and <path>'s own revision history.
#       Two sections:
#         downstream:   every path reachable from <path> by following
#                       Derives-From trailer values forward, transitively,
#                       one per line. The node at each hop is the deriving
#                       commit's changed file(s) — the artefact the commit
#                       introduces — not the trailer value, which names the
#                       hop's source. A visited-set bounds the walk so it
#                       terminates. <path> itself is never listed.
#         revises:      one line per commit carrying `Revises: <path>`,
#                       i.e. <path>'s own revision history. This lookup is
#                       flat, never transitive: a Revises trailer is never
#                       followed as a forward edge.
#       Edges are read from trailer fields
#       (`git log --all --format='%(trailers:key=Derives-From,valueonly)'`
#       and the Revises equivalent), never from a commit subject.
#   outstanding-deferrals
#       Print every outstanding deferral found on the resolved trunk (local
#       dev, then local develop, then the branch named by
#       refs/remotes/origin/HEAD — this subcommand's own trunk-only mode;
#       downstream and closed-paths keep scanning --all and are unchanged).
#       No argument. Purely mechanical, no model step, like downstream.
#       Per D (the artefact a Defers: trailer names), walk trunk commits in
#       a single `git log <trunk> --topo-order --reverse` pass and track
#       the latest of Reconciles: D, Confirms: D or Defers: D <origin>
#       <condition> seen; D is outstanding only when that latest event is
#       a Defers:. For each outstanding D, due is true when any later
#       commit (strictly after the Defers: commit, in that same ordering)
#       carries Reconciles:, Revises: or Derives-From: naming the
#       deferral's own origin path — distinct from the D-verdicts above,
#       which decide outstanding-ness, not due-ness. Prints one record per
#       outstanding deferral, separated by a blank line: D:, origin:,
#       condition: (the raw value after D, unmodified, including the
#       origin token), due: true|false, and zero or more
#       candidate: <short-hash> <subject> lines, present only when due is
#       true. Reads Defers:/Reconciles:/Confirms:/Revises:/Derives-From:
#       trailers via `git log <trunk> --format=...`, never a commit
#       subject.
#
# Exit codes
#   0  the query ran and its sections were printed
#   2  usage or a precondition failed (unknown subcommand, missing
#      argument, or not inside a git repository)
#
# Depends on git and nothing else.

set -u

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# Print, one per line, every Derives-From edge in the whole history as
# `<source-path><TAB><derived-path>`: the source is the trailer value, the
# derived path is a changed file of the commit carrying the trailer. One
# git pass over every commit on every branch; a commit with several
# Derives-From values or several changed files yields one line per pair.
# Merge commits show no files under --name-only, which is correct: an
# artefact's introducing commit (which carries the trailer) is never the
# merge.
#
# Scanned line by line (default newline RS) rather than with a record
# separator: BSD awk (macOS) treats `-v RS='\0'` as paragraph mode, so a
# NUL-delimited multi-line record is not portable. Each commit emits a
# header line marked with \x1e carrying its Derives-From values (joined by
# \x1d), then its changed files one per line; \x1e/\x1d/\x1f escapes are
# honoured inside the awk body.
df_edges() {
  git log --all --name-only \
    --format='%x1eDF%x1f%(trailers:key=Derives-From,valueonly,separator=%x1d)' |
  awk '
    substr($0, 1, 1) == "\x1e" {
      split(substr($0, 2), h, "\x1f")   # h[1]="DF", h[2]=joined DF values
      ndf = split(h[2], dfs, "\x1d")
      next
    }
    $0 == "" { next }
    {
      for (j = 1; j <= ndf; j++) if (dfs[j] != "") printf "%s\t%s\n", dfs[j], $0
    }'
}

# Print, one line per commit (`<short-hash> <subject>`), every commit (on
# any branch) carrying a Revises trailer whose value is exactly $1. Flat:
# this is $1's own revision history, never a forward edge to follow. One
# git pass.
revises_of() {
  local p="$1"
  # Split on the \x1f and \x1e separators inside the awk body: BSD awk
  # (macOS) does not honour a \xNN escape passed via -F, only one used in
  # a split() call.
  git log --all \
    --format='%h%x1f%s%x1f%(trailers:key=Revises,valueonly,separator=%x1e)' |
  awk -v p="$p" '
    {
      k = split($0, a, "\x1f")
      if (k < 3) next
      n = split(a[3], rs, "\x1e")
      for (i = 1; i <= n; i++) if (rs[i] == p) { print a[1] " " a[2]; break }
    }'
}

cmd_downstream() {
  local query="${1:-}"
  [ -n "$query" ] || { usage >&2; return 2; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf 'history: not inside a git repository\n' >&2; return 2; }

  # Read every Derives-From edge once, then walk it breadth-first, forward
  # and transitive. The visited set seeds with the query so the query is
  # never emitted and the walk terminates on cycles.
  local edges; edges="$(df_edges)"
  local -a queue=("$query") results=()
  local visited=" $query " cur f
  while [ ${#queue[@]} -gt 0 ]; do
    cur="${queue[0]}"
    queue=("${queue[@]:1}")
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$visited" in *" $f "*) continue ;; esac
      visited="$visited$f "
      results+=("$f")
      queue+=("$f")
    done < <(printf '%s\n' "$edges" | awk -F'\t' -v s="$cur" '$1 == s { print $2 }')
  done

  printf 'downstream:\n'
  if [ ${#results[@]} -gt 0 ]; then
    for f in "${results[@]}"; do printf '%s\n' "$f"; done
  fi
  printf 'revises:\n'
  revises_of "$query"
}

_lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# Print the lightly-stemmed words of the topic $1, space-separated. Each
# word (length >= 3) is emitted as itself and, when a trailing -ing/-ies/
# -es/-s is stripped, also as its stem, so "limiting" matches "limit" and
# "rate-limited". The prune matches on any of these as a substring, which
# is what makes it recall-biased.
_topic_stems() {
  local topic w stem out=""
  topic="$(_lc "$1")"
  for w in $(printf '%s' "$topic" | tr -cs 'a-z0-9' ' '); do
    [ ${#w} -ge 3 ] || continue
    out="$out $w"
    stem="$w"
    case "$w" in
      *ing) stem="${w%ing}" ;;
      *ies) stem="${w%ies}" ;;
      *es)  stem="${w%es}" ;;
      *s)   stem="${w%s}" ;;
    esac
    if [ ${#stem} -ge 3 ] && [ "$stem" != "$w" ]; then out="$out $stem"; fi
  done
  printf '%s' "$out"
}

# Succeed when any stem in $1 is a substring of the (lowercased) text $2.
_matches() {
  local stems="$1" text s
  text="$(_lc "$2")"
  for s in $stems; do
    case "$text" in *"$s"*) return 0 ;; esac
  done
  return 1
}

# Print one line per bullet of the file's `## Alternatives considered`
# section, continuation lines folded in. A bullet is a line starting `- `
# or `* `; a following indented line continues it; a blank line or the
# next `## ` heading ends it.
_alt_bullets() {
  awk '
    /^##[ \t]+[Aa]lternatives/ { inalt = 1; next }
    /^## / { if (inalt) { if (buf != "") { print buf; buf = "" } inalt = 0 } }
    inalt {
      if ($0 ~ /^[-*][ \t]+/) {
        if (buf != "") { print buf; buf = "" }
        line = $0; sub(/^[-*][ \t]+/, "", line); buf = line
      } else if ($0 ~ /^[ \t]+[^ \t]/) {
        if (buf != "") { c = $0; sub(/^[ \t]+/, "", c); buf = buf " " c }
      } else if ($0 ~ /^[ \t]*$/) {
        if (buf != "") { print buf; buf = "" }
      }
    }
    END { if (inalt && buf != "") print buf }
  ' "$1"
}

# Print the hash of every commit (on any branch) carrying a Revises
# trailer whose value is exactly $1.
_revising_commits() {
  git log --all --format='%H%x1f%(trailers:key=Revises,valueonly,separator=%x1e)' |
  awk -v p="$1" '
    {
      k = split($0, a, "\x1f")
      if (k < 2) next
      n = split(a[2], rs, "\x1e")
      for (i = 1; i <= n; i++) if (rs[i] == p) { print a[1]; break }
    }'
}

# Print the reason text of commit $1: its body folded to one line, with
# the trailer block and blank lines removed.
_body_reason() {
  git show -s --format='%b' "$1" |
  grep -viE '^(Revises|Derives-From|Clarifies|Completes|Abandons|Consumed-By|Co-Authored-By|Signed-off-by):' |
  awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") printf "%s%s", (n++ ? " " : ""), $0 } END { if (n) print "" }'
}

cmd_closed_paths() {
  local topic="${1:-}"
  [ -n "$topic" ] || { usage >&2; return 2; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf 'history: not inside a git repository\n' >&2; return 2; }

  local stems; stems="$(_topic_stems "$topic")"

  printf 'closed-paths:\n'
  local f title bullets b h reason
  for f in docs/adr/*.md; do
    [ -e "$f" ] || continue
    title="$(grep -m1 '^title:' "$f" | sed 's/^title:[[:space:]]*//')"
    bullets="$(_alt_bullets "$f")"
    # Recall-biased prune, at ADR granularity: if the title or any bullet
    # is on topic, every one of this ADR's candidates survives.
    _matches "$stems" "$title
$bullets" || continue
    # Alternatives candidates, one record per bullet.
    printf '%s\n' "$bullets" | while IFS= read -r b; do
      [ -n "$b" ] || continue
      printf 'path: %s\nsource: alternatives\nreason: %s\n\n' "$f" "$b"
    done
    # Revises candidates, one record per revising commit.
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      reason="$(_body_reason "$h")"
      printf 'path: %s\nsource: revises\nreason: %s\n\n' "$f" "$reason"
    done < <(_revising_commits "$f")
  done
}

# Resolve this repository's trunk (Mechanism 4): local dev, then local
# develop, then the branch named by refs/remotes/origin/HEAD. Reimplements
# skills/git-workflow/scripts/git-workflow.sh's derive_trunk ladder rather
# than sourcing that script, so this script keeps its header claim to
# depend on git and nothing else. Prints the trunk's branch name and
# returns 0, or returns 1 with nothing printed when none resolves.
_derive_trunk() {
  if git rev-parse --verify --quiet refs/heads/dev >/dev/null; then
    printf 'dev\n'; return 0
  fi
  if git rev-parse --verify --quiet refs/heads/develop >/dev/null; then
    printf 'develop\n'; return 0
  fi
  local head
  if head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "${head#origin/}"; return 0
  fi
  return 1
}

# Print, one line per commit on $1 (the trunk) in `--topo-order --reverse`
# order (Mechanism 3), the fields `cmd_outstanding_deferrals` needs:
# `<short-hash>\x1f<subject>\x1f<Defers values>\x1f<Reconciles values>\x1f
# <Confirms values>\x1f<Revises values>\x1f<Derives-From values>`, each
# trailer field's multiple values (a commit may carry a key more than
# once) joined by \x1d. One git pass.
_outstanding_deferrals_log() {
  local trunk="$1"
  git log "$trunk" --topo-order --reverse \
    --format='%h%x1f%s%x1f%(trailers:key=Defers,valueonly,separator=%x1d)%x1f%(trailers:key=Reconciles,valueonly,separator=%x1d)%x1f%(trailers:key=Confirms,valueonly,separator=%x1d)%x1f%(trailers:key=Revises,valueonly,separator=%x1d)%x1f%(trailers:key=Derives-From,valueonly,separator=%x1d)'
}

cmd_outstanding_deferrals() {
  [ $# -eq 0 ] || { usage >&2; return 2; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf 'history: not inside a git repository\n' >&2; return 2; }

  local trunk
  trunk="$(_derive_trunk)" || {
    printf 'history: no trunk resolves: looked for refs/heads/dev, refs/heads/develop and the branch named by refs/remotes/origin/HEAD\n' >&2
    return 2
  }

  # Mechanisms 2, 3, 5, 6, 7. A single pass over the trunk's trailers
  # (oldest first, per _outstanding_deferrals_log's ordering) tracks, per
  # D, the latest of {Defers: D <origin> <condition>, Reconciles: D,
  # Confirms: D} (Mechanism 5) and collects every Reconciles:/Revises:/
  # Derives-From: value seen, with its sequence number, as a candidate
  # due-trigger pool (Mechanism 6). The END block then reports every D
  # whose latest event is still a Defers:, checking that pool for any
  # entry whose value matches that deferral's origin with a strictly
  # greater sequence number than the Defers: commit's own.
  # Note: fields are split with split($0, f, "\x1f") rather than
  # `-F'\x1f'`/FS, because macOS's awk does not expand a \x escape given
  # on the command line (or in FS) but does expand one inside a string
  # literal passed to split().
  _outstanding_deferrals_log "$trunk" | awk '
    function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
    {
      split($0, f, "\x1f")
      h = f[1]; subj = f[2]; defers = f[3]; reconciles = f[4]; confirms = f[5]; revises = f[6]; derivesfrom = f[7]
      seq = NR

      if (defers != "") {
        nd = split(defers, dlist, "\x1d")
        for (i = 1; i <= nd; i++) {
          v = trim(dlist[i])
          if (v == "") continue
          if (!match(v, /^[^ \t]+/)) continue
          D = substr(v, RSTART, RLENGTH)
          rest = v
          if (match(rest, /^[^ \t]+[ \t]+/)) { rest = substr(rest, RSTART + RLENGTH) } else { rest = "" }
          origin = ""
          if (match(rest, /^[^ \t]+/)) origin = substr(rest, RSTART, RLENGTH)
          if (!(D in seen)) { seen[D] = 1; dorder[++dn] = D }
          state[D] = "defer"
          origin_for[D] = origin
          cond_for[D] = rest
          defer_seq[D] = seq
        }
      }

      if (reconciles != "") {
        nr = split(reconciles, rlist, "\x1d")
        for (i = 1; i <= nr; i++) {
          v = trim(rlist[i])
          if (v == "") continue
          if (v in state) state[v] = "reconciled"
          te++; tseq[te] = seq; th[te] = h; ts[te] = subj; tval[te] = v
        }
      }

      if (confirms != "") {
        nc = split(confirms, clist, "\x1d")
        for (i = 1; i <= nc; i++) {
          v = trim(clist[i])
          if (v == "") continue
          if (v in state) state[v] = "confirmed"
        }
      }

      if (revises != "") {
        nv = split(revises, vlist, "\x1d")
        for (i = 1; i <= nv; i++) {
          v = trim(vlist[i])
          if (v == "") continue
          te++; tseq[te] = seq; th[te] = h; ts[te] = subj; tval[te] = v
        }
      }

      if (derivesfrom != "") {
        nf = split(derivesfrom, flist, "\x1d")
        for (i = 1; i <= nf; i++) {
          v = trim(flist[i])
          if (v == "") continue
          te++; tseq[te] = seq; th[te] = h; ts[te] = subj; tval[te] = v
        }
      }
    }
    END {
      for (i = 1; i <= dn; i++) {
        D = dorder[i]
        if (state[D] != "defer") continue
        origin = origin_for[D]
        cond = cond_for[D]
        dseq = defer_seq[D]
        due = "false"
        cands = ""
        for (j = 1; j <= te; j++) {
          if (tval[j] == origin && tseq[j] > dseq) {
            due = "true"
            cands = cands "candidate: " th[j] " " ts[j] "\n"
          }
        }
        printf "D: %s\n", D
        printf "origin: %s\n", origin
        printf "condition: %s\n", cond
        printf "due: %s\n", due
        if (due == "true") printf "%s", cands
        printf "\n"
      }
    }
  '
}

main() {
  if [ $# -eq 0 ]; then usage >&2; return 2; fi
  case "$1" in
    -h|--help) usage; return 0 ;;
    downstream) shift; cmd_downstream "$@" ;;
    closed-paths) shift; cmd_closed_paths "$@" ;;
    outstanding-deferrals) shift; cmd_outstanding_deferrals "$@" ;;
    *) printf 'history: unknown subcommand: %s\n' "$1" >&2; usage >&2; return 2 ;;
  esac
}

main "$@"
