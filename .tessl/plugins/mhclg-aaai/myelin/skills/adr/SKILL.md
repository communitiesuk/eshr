---
name: adr
description: Architecture Decision Records (ADRs) capture WHAT was decided and WHY, for durable reference. TRIGGER when starting a new decision, spec, or design record — before any implementation planning. SKIP for pure action lists (use the `plans` skill for those). ADRs are the reference material; plans are the action lists that derive from them.
---

# Architecture Decision Records (ADRs)

ADRs capture decisions: what was chosen, why it was chosen, what trade-offs were accepted. They are durable reference material — a new agent or human reads them to orient to the project's intent and history. ADRs do **not** contain action lists, task workflows, or progress state — those live in `plans/` (see the `plans` skill).

## Before writing

Read every ADR in `docs/adr/` before writing a new one. The tree holds only current decisions, so this is the complete set of what is decided, and reading it is a bounded task.

- Do not write an ADR that answers a question an existing ADR already answers. Revise that one (see "Revising an ADR").
- Do not adopt a path an existing ADR's Alternatives section rejects without saying, in the new ADR's Alternatives section, why the rejection no longer holds.

## If you are a drafter subagent

You draft or revise the artefact your task names, from the inputs it
gives you.

- Edit files, and never commit: the parent makes every commit.
- End your report with a numbered list of the issues you found:
  ambiguities in the upstream, conflicts with a recorded decision or
  with this skill, and choices you made that nothing settles.
- Aim for concision and consistency, but do not let them hold you up.
- When you revise existing text, act only on the recorded decisions
  and any change you are applying. Apply each by cutting text where
  that loses no fidelity, consistency or verifiability; then by
  replacing it, which includes correcting it, aiming to lower the
  character count. Add text only as a last resort.
- Finish the whole task, even after you find an escalation.

## Drafting and review

If you are a drafter or reviewer subagent, skip this section.

The harness states this skill's base directory when it loads the
skill. Call that `$SKILL_DIR`.

### The upstream: the summary

An ADR's upstream is the summary, plus the discovery note where one
exists, plus any changes requested at acceptance. You never write the
summary and never filter the conversation.

**What starts drafting.** Only an explicit request from the human to
write the ADR starts drafting. Without one, draft nothing: ask the
human, or, with no human available, stop and report that no ADR was
drafted, and why.

**The summary.** The summariser always runs on the conversation, even
when a discovery note exists. In a one-turn task, the conversation is
the task text.

1. Write the dialogue to a file in the session's temporary directory,
   outside the repository, with the adapter:
   `bash "$SKILL_DIR/scripts/claude-code-dialogue.sh" "$CLAUDE_CODE_SESSION_ID" "<the directory the session started in>" "<file>"`.
   Where the adapter cannot produce the dialogue (it exits 1, it
   writes a dialogue with no `### Human` block,
   `$CLAUDE_CODE_SESSION_ID` is unset, or the harness is not Claude
   Code), write the dialogue out yourself in the format of
   `references/dialogue.md`, unfiltered, with `Mode: fallback`. That
   mode is degraded: copy verbatim and leave nothing out. Never commit
   the dialogue file.
2. Give a summariser subagent `references/summariser.md` as its
   instructions, and the dialogue file's path and the ADR's question as
   its inputs. Do not summarise yourself.
3. Give the drafter the summariser's text verbatim. Never edit it on
   your own initiative.

An ADR's round-1 record names the summariser's model in its `Models:`
line: `Models: drafter <model>, reviewer <model>, summariser <model>.`

**Approval, only when the human asks.** The human need not approve the
summary before drafting, but may ask to. Then show the human the
summary verbatim, as the exact text the drafter will receive, and
draft only once the human approves it. If the human asks for changes,
apply those changes and no others, show the changed text, and draft
only once the human approves that.

Anything you work out that the ADR needs must be said in the
conversation, because the summariser sees only the dialogue.

### The flow

1. Settle the upstream, above.
2. Begin the ADR's branch (`git-workflow`), unless you are already on
   it with an unreviewed draft.
3. Run the review loop below. Round 1's draft is the introducing
   commit, or, for a revision of an accepted ADR, the first revising
   commit.
4. When the loop has finished, land the branch (`git-workflow` `land`,
   exit 3). Give the human the reviewed ADR, the pull request where
   there is one, the review record, and every escalation with its
   reason. Review finishes before the human is asked to accept; the
   human's merge accepts.

With no human available and an explicit request, run this flow to the
pull request and stop: land, then report the pull request where there
is one, and each escalation with its reason. Nothing is merged, and
you do not wait for an answer.

### Changes requested at acceptance

A change the human requests at acceptance is the human's decision and
joins the upstream. It takes precedence over the summary,
over any earlier change, and over any recorded decision of yours that
it contradicts.

1. Record it first, in an empty commit of its own titled
   `Record changes requested at acceptance of <path>`, whose body opens
   `Changes requested at acceptance.` and quotes the human's text
   verbatim.
2. Restart the loop at round 1, under the same rules. Round 1 is the
   revision applying the change, and its review. Its drafter gets the
   upstream, the current draft and the recorded decisions. Its records
   open as "The record" below gives after a restart, and round 1's
   marks under `Superseded:` each recorded decision the change
   contradicts. A reviewer does not flag the change.
3. When the loop finishes, land again and ask the human to accept
   again.

An answer to an escalation that changes the draft is a change
requested at acceptance, whenever it is given. An answer that leaves
the draft as it stands is recorded in an empty commit titled
`Record the human's answer on <path>`, whose body opens as "The
record" below gives for the human's answer, for the last round, and
quotes it. Later reviewers treat it as settled.

<!-- review-loop:begin -->
### The review loop

The loop runs whenever this skill drafts an artefact or revises what
one decides. It does not run for a typo fix.

**Roles.** Each subagent has one small task, and every subagent is
fresh: none is resumed from an earlier round.

- You, the **parent**, run the loop. You never draft and never
  review. You make every commit on the artefact's branch; drafters and
  reviewers edit or read files and never commit.
- A **drafter** subagent drafts or revises the artefact. Its
  instructions are this skill; the repository, and what this skill
  tells it to read, are part of those instructions, not of the
  upstream. Its report ends with a numbered list of
  the issues it found: ambiguities in the upstream, conflicts with a
  recorded decision or with this skill, and choices it made that
  nothing settles. A cheaper model may draft.
- A **reviewer** subagent reviews the draft. Its instructions are
  `references/review.md`. Its model is at least as strong as the
  drafter's. It never edits the artefact.

**Inputs.** The upstream is what the artefact is checked against. The
recorded decisions are the bodies of the commits on the branch since
the fork point (`git log --format=%B <trunk>..HEAD`), which hold every
round's record, including any earlier loop's.

| Subagent | Gets |
| --- | --- |
| Drafter, round 1 of the first loop | the upstream |
| Drafter, every other round, and the closing pass | the upstream, the current draft, the recorded decisions |
| Reviewer, every round | the upstream, the draft, the recorded decisions |

No subagent gets your reasoning, or any deliberation the record does
not hold.

**A round.**

1. A fresh drafter drafts or revises. Commit the draft. Round 1's is
   the introducing commit (or a revision's first revising commit). A
   later round's is titled `Revise <path> (round N draft)`. A draft
   commit carries its title, the summary and trailers where
   this skill requires them, and the body a `Revises` commit requires
   (what changed and why); never the drafter's deliberation or yours. An
   unreviewed draft already on the branch is round 1's draft: the loop
   starts at its review, and round 1's record gives the drafter as
   `not a subagent`.
2. A fresh reviewer reviews the committed draft.
3. When both have reported, and not before, decide on both lists
   together. Make no decision before the first draft. Each High is
   fixed by the next round's drafter. Each Medium or Low is fixed in a
   later round or the closing pass, or the record says why not. A
   choice the upstream did not settle is yours. Collect every
   escalation.
4. Commit the round's record before anything else happens on the
   branch, as an empty commit
   (`git commit --allow-empty --cleanup=whitespace -F <file>`) titled
   `Record review round N of <path>`.

**The record.** Its body, in this order:

```
Review record, round N.
Models: drafter <model>, reviewer <model>[, summariser <model>].
Drafter's issues: each numbered, with "Decided:" and a short reason.
Reviewer's findings: each numbered, with its severity, "Decided:" and a short reason.
Highs from round N-1: each "confirmed fixed" or "reopened".
Superseded: each recorded decision a change requested at acceptance contradicts.
Escalated: each with its reason, or "none".
Next: round N+1, closing pass, stop, or stopped for the human.
```

Every record's first line has this form, its suffixes in this order:
`Review record, round N.`; after the K-th restart,
`Review record, round N, restart K.`; for the human's answer, add
`, the human's answer` last, as in
`Review record, round N, restart K, the human's answer.`

It carries no artefact-graph trailer (`Derives-From`, `Revises`,
`Consumed-By`, `Completes`, `Abandons`).

Outside any git repository, run the loop and report the records
instead of committing them.

**Stop rule (provisional).** Only High findings trigger another round.
Stop after a round whose review leaves no High open. Run at most 3
rounds, counting the first. If a High is still open after round 3, the
loop ends and that High is escalated.

**The closing pass.** When the loop stops with issues or Medium or Low
findings you decided to act on, a fresh drafter applies them. The pass
is not a round and is not re-reviewed. Check that the change matches
the recorded decisions and does nothing else; if it does not, a fresh
drafter redoes the pass. Commit it titled
`Apply the closing pass to <path>`, its body opening `Closing pass.`,
then the drafter's model, each decision applied, and
`Checked by the parent: the change matches the recorded decisions and nothing else.`

**Escalation.** Surface these to the human, and do not resolve them
yourself:

- a finding whose fix would change something the human has already
  agreed: a summary the human approved, a change requested at
  acceptance, or an accepted ADR (for example, a plan review showing
  that the ADR needs revising);
- a High still open after round 3;
- a reviewer finding that a recorded decision of yours contradicts the
  upstream.

Escalations are batched. A drafter or reviewer that finds one carries
on to the end of its task. Surface all of a round's escalations
together, each with its reason, at the point this skill names.

**With no human available**, as in a one-turn task, stop and report
at that point, naming each escalation and its reason. Make no further
round commit.

**The pull request.** Where there is one, its description is every
commit's message and body, so it repeats every round's record. `land`
writes it, and rewrites it when the branch lands again.
<!-- review-loop:end -->

## Location and naming

- **Directory**: `docs/adr/` at the project root. Create it if it doesn't exist.
- **Filename**: `NNNN-kebab-slug.md`. `NNNN` is a zero-padded monotonic number — pick the next unused by `ls docs/adr/ | sort | tail -1`. Slug is a short lowercase description.
  - Examples: `0001-azure-service-principal-auth.md`, `0007-migrate-from-langchain.md`.
- **One ADR per question.** The title of an ADR is the question it answers. The test for whether a revision is an edit or a new ADR: if the revision still answers the title's question, edit in place; if it answers a new question, write a new ADR, and edit the old one only where the new decision changes it. Filenames are unaffected by this rule — the slug stays a short description, not the question.

## Frontmatter

```yaml
---
title: <the question this ADR answers, matches the H1>
date: YYYY-MM-DD
---
```

- **title**: phrased as the question the ADR answers, ending in a question mark. Matches the H1.
- **date**: ISO date the ADR was first written. Never updated on later edits — git history is authoritative for that.
- There is no `status` field. Where an ADR is says whether it is accepted (see "Proposed and accepted"). Do not add one.

## Proposed and accepted

- **Proposed**: not yet on the trunk. The ADR is on its own branch (the branch that adds it), and in that branch's pull request once one is open. It may change during review.
- **Accepted**: on the trunk. It is the current decision of record, and it stays accepted while a revision of it is proposed on another branch. It may or may not be implemented yet. Implementation state is tracked in the corresponding `plans/` entry, not here.
- **The human's merge is the act of accepting.** The merge commit records who accepted and when. There is nothing to set or flip.
- **Not accepting** is either asking for changes, after which work continues on the branch, or closing the pull request unmerged. An ADR whose pull request is closed unmerged was not accepted and is no longer proposed. It never reaches the trunk.

A decision that is reversed outright is deleted, not marked. The commit that deletes it says why.

## Revising an ADR

An ADR is not frozen at merge. When the answer to its question changes, edit it in place. The superseded text is in the history of the file, reachable with `git log --follow -p`.

- The commit that changes what an accepted ADR decides carries this trailer, copied exactly:

  ```
  Revises: docs/adr/NNNN-<slug>.md
  ```

  The value is the repository-relative path of the ADR. The commit body says, in sentences, what changed and why. Trailer and body are both mandatory.
- On a revision branch, the first revising commit carries `Revises`,
  and its body carries both the reason (what changed and why) and the
  summary, as the introducing commit does (see "The
  introducing commit"). Later commits on the same branch,
  round records and revisions alike, are drafting of that revision and
  carry no trailer: the `Revises` edge is added by exactly one commit.
- When a revision reverses an adopted path, add an entry to the Alternatives section summarising the reversal: what was previously decided and why it was reversed. That is what stops the next author retrying it; the full prior text is in history.
- Everything downstream of the ADR is accounted for on the same branch (ADR 0011). `history downstream docs/adr/NNNN-<slug>.md` lists it — plans, and the skills and code they produced — and `begin` prints the same list as a worklist. For each downstream still in the tree, either edit it to match on this branch and record `Reconciles: <path>`, or leave it: `land` records `Defers: <path> <this ADR> until a plan derives from it` for each one that still has no verdict, and the plan that later derives from this ADR discharges each deferral with `Reconciles:` or `Confirms:` (ADR 0012). The verdict trailers and the gate are in the `git-workflow` skill (Rule 9, Rule 15). Do not use a plan's `deferred` status for this; that status is for paused work, not for a revision's downstreams.
- `Revises` is for changes to what an accepted ADR decides; a standalone non-revising edit — a typo fix, a citation repair, a metadata change, or an uncaught cross-reference — carries `Clarifies` instead, and `land` sends it direct to trunk with no human pull request. Ride-along on the causing branch is preferred when the cross-reference is caught at the referencing artefact's own creation; `Clarifies` is for the same kind of edit made standalone, after the fact. An edit made on the ADR's own branch before it merges is still drafting and carries no trailer.

## The introducing commit

The first commit on the ADR's branch carries `Derives-From: <path>` for each discovery note the ADR derives from, where one exists — one trailer per note. Direct upstreams only.

Its body carries the summary verbatim, between a line
`# Confirmed decision summary` and a line
`# End of confirmed decision summary`, before any trailers. The text
between the markers is exactly what the drafter received, and its
last line names the mode that produced it: `Mode: adapter (claude-code)`
or `Mode: fallback`. Commit with
`git commit --cleanup=whitespace -F <file>` so the heading lines
survive. The summary adds no edge to the artefact graph and no trailer.

## Body

After the frontmatter and `#` H1:

1. **Forward-pointer** — a directive block for whoever implements this ADR. See "Required forward-pointer" below. This is the first section of the body.
2. **Context** — the problem or need. What prompted the decision.
3. **Decision** — plainly, what was chosen. Include the shape of the resulting behaviour (interface, precedence, invariants). This section is the spec that plans will implement against.
4. **Alternatives considered** — the options rejected and why.
5. **Consequences** — what this makes easier, what it rules out, what will need to be revisited.
6. **References** — each ADR whose decision this one relies on or constrains, with a phrase saying which, plus external material. References records what a decision uses; `Derives-From` on the introducing commit records what the artefact was produced from. The two are different relations.

Omit sections that would be empty (except Forward-pointer, which is required). Keep it tight — a reader should be able to scan an ADR in under two minutes. That caps a new ADR: one that goes over it is cut, not split. An existing ADR over it is a candidate for decomposition.

## Required forward-pointer

Every ADR body must open with a directive block, placed immediately after the H1 and before the Context section, so that anyone reading the ADR to implement it encounters the instruction first.

- **Placement**: immediately after the H1.
- **Tone**: directive, not advisory. Use "invoke", not "consider".
- **Content**: instruct the implementer to invoke the `plans` skill when acting on this ADR.

Minimal form:

```markdown
> **Directive for the implementer**: when implementing this ADR, invoke the `plans` skill to produce the corresponding plan artifact. Do not begin implementation without a plan.
```

The directive lives in the artifact — not the skill body — so it survives context compaction and is re-read every time an implementer opens the ADR.

## What does NOT belong in an ADR

- Ordered task lists ("first do X, then Y")
- Test lists, verification steps
- Progress state ("done", "blocked")
- Names of files being edited *for this cycle of work* (though listing which module owns the decided behaviour is fine)

All of the above belong in `plans/NNNN-*.md`.

## Do not

- Do not put decisions in `plans/`. Plans reference ADRs; they don't replace them.
- Do not write a new ADR to change the answer to a question an existing ADR already answers. Revise it.
- Do not keep a reversed ADR in the tree under a status flag. Delete it; the commit and git history are the record.
