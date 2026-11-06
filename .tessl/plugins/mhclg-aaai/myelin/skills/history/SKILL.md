---
name: history
description: The history skill retrieves three things from git history — closed paths (for a topic, which decisions are already closed, each with its reason and source), the artefact graph (what derives from or revises a given artefact, transitively), and outstanding deferrals (which deferred conditions are due a recheck). TRIGGER before drafting or reviewing an ADR, or planning a revision, when you need to know whether a topic is already closed, or what derives from or revises artefact X. SKIP for human open-ended history browsing, for detecting whether a topic is still "open", and for tuning the prune at scale — all deferred by ADR 0010.
---

# The history skill

Completed and superseded artefacts leave the working tree (see the
`git-workflow` and `adr` skills), so what is decided and what derives
from what lives in git history. This skill retrieves it, for three
questions that arise before you draft or review an ADR, plan a
revision, or land an artefact carrying a deferral:

- **Closed paths** — for a topic, which decisions are already closed,
  each with its reason and its source. The ADR reviewer's check that a
  draft does not reopen a settled path.
- **Downstream / the graph** — what derives from, or revises, a given
  artefact, transitively. What a revision must carry downstream so no
  plan or implementation is left stranded against a changed decision.
- **Outstanding deferrals** — which deferred conditions (`Defers:`
  trailers) are still outstanding, and which of those are due a
  recheck because their triggering condition has since landed.

All three are deterministic retrievals over git trailers and in-tree
ADR sections. A script does the retrieval; exactly one narrow model
step runs, and only for the closed-paths relevance judgement.

The harness states this skill's base directory when it loads the skill.
Call that `$SKILL_DIR`; the script is run with Bash, never by path
alone:

```sh
bash "$SKILL_DIR/scripts/history.sh" --help
```

## The downstream / graph question

Run the query and report its output. There is no model step.

```sh
bash "$SKILL_DIR/scripts/history.sh" downstream <path>
```

`<path>` is the full repository-relative path of the artefact (for an
ADR, `docs/adr/NNNN-<slug>.md`), never its bare number. The script
prints two sections:

- `downstream:` — every artefact reachable from `<path>` by following
  `Derives-From` edges forward and transitively (an ADR's plans, and
  the code those plans produced). `<path>` itself is never listed.
- `revises:` — one line per commit that revises `<path>`, i.e. its own
  revision history.

Report both. For a revision, the `downstream:` list is what must be
checked against the changed decision. An empty `downstream:` section is
an answer — nothing derives from `<path>` — not a reason to go reading
`git log` by hand.

## The closed-paths question

Run the query, then make the one bounded relevance-and-dedupe judgement
on its output.

```sh
bash "$SKILL_DIR/scripts/history.sh" closed-paths <topic>
```

`<topic>` is an artefact path, a keyword, or a candidate ADR title. The
script prints a recall-biased set of candidate records — more than are
on the topic, by design — each with a `path:`, a `source:`
(`alternatives` for an ADR's own `## Alternatives considered` bullet,
`revises` for the body of a commit that revised it) and a `reason:`.
Candidates are grouped by the ADR path they concern. The script dedupes
nothing and judges no relevance; that is this step's single job.

The judgement, over the printed candidates only:

1. **Relevance.** Keep only the candidates that are on the topic.
   Judge each using **only its printed `reason:` text** — never open
   the ADR or read `git log`. The reason is already a written summary
   of the closed path, so the judgement is narrow. The prune is
   recall-biased, so expect to discard some candidates here.
2. **Dedupe.** When two kept candidates are grouped under the **same
   ADR path** and describe the **same reversed decision** — one sourced
   `alternatives`, one sourced `revises` — collapse them to one,
   keeping the `alternatives`-sourced candidate (the in-tree
   restatement). Candidates under different paths, or describing
   different decisions, are never collapsed.

This judgement's only inputs are the topic and the candidates' `reason:`
text; its only output is which candidates survive. It may be done
inline, or handed to a fresh, narrow subagent in the one-small-task
style `docs/adr/0008-stage-reviews.md` established.

Report the surviving closed paths, each with its reason and its source.
If no candidate is printed, or none survives the judgement, report that
nothing is closed on the topic — do not fall back to reading `docs/adr/`
or `git log` by hand.

## The outstanding-deferrals question

Run the query and report its output. There is no model step.

```sh
bash "$SKILL_DIR/scripts/history.sh" outstanding-deferrals
```

No argument: the query always runs against the resolved trunk (never
`--all`). The script prints one record per outstanding deferral,
separated by a blank line: `D:` (the deferred artefact), `origin:` (the
path whose landing re-triggers the check), `condition:` (the full
condition text, unmodified, including the origin token), `due:`
(`true` or `false`), and, only when `due: true`, one `candidate:
<short-hash> <subject>` line per commit that may have discharged the
condition.

Report every record. For a `due: true` record with more than one
`candidate:` line, judging which candidate (if any) actually satisfies
the condition's free-text description is your own narrow read of the
`condition:` text against each candidate's subject — the script never
does this matching; candidacy (who triggered a recheck) is the whole
of what it decides.

## Do not

- Do not read `docs/adr/` or run `git log` directly to answer either
  question. This skill exists so that neither is read by hand; the
  script reads the trailers and the Alternatives sections for you.
- Do not key the graph on an artefact's number. Numbers are reused
  (`plans/0004-releases.md` and `plans/0004-where-does-history-live.md`
  are different artefacts); the full path is the key, and the script
  uses it.
- Do not judge a closed path's relevance by re-reading the ADR. Judge
  on the printed `reason:` text alone — that is what keeps the model
  step narrow.
- Do not drop a candidate the script printed for any reason other than
  the relevance-and-dedupe judgement above. A false negative silently
  reopens a closed path.
