---
name: plans
description: Plans are ordered action lists that implement an ADR. TRIGGER when about to start executing a decision — writing steps, tests, verification, tracking progress. SKIP for capturing a decision itself (use the `adr` skill for that). Plans always derive from ADRs; projects can only implement what has been decided.
---

# Plans

Plans are the action side of the ADR/plan pair. Where an ADR captures *what was decided and why*, a plan captures *what happens next and in what order*. Plans are ephemeral in nature: they live in the tree while their work is intended and leave it when the work is done or abandoned. Git history holds what has been finished.

## Foundational rule — plans always derive from ADRs

**Plans always derive from ADRs. Projects can only implement what has been decided.**

Before writing a plan, verify that its ADR is accepted: on the trunk, in `docs/adr/`. An ADR carries no status field; where it is says which (see the `adr` skill). `git cat-file -e <trunk>:docs/adr/NNNN-<slug>.md` succeeds if and only if the ADR is on the trunk. Outside any git repository there is no trunk, so no ADR is accepted.

If the ADR is only proposed, on its own branch or in its pull request, do not write the plan. Say that the plan waits for the ADR's acceptance, the human's merge, and stop. An ADR whose pull request was closed unmerged is neither proposed nor accepted; treat it as absent. If no ADR exists:

1. Stop.
2. Discuss what needs to be done with the user, confirming decisions to capture.
3. Say that an ADR is needed first, and ask whether to write it; the `adr` skill starts only on the human's explicit request.
4. Write the plan once the ADR is accepted.

Asked only for a plan, with no human available, stop and report that an ADR is needed first. Write neither the ADR nor the plan.

Every plan's frontmatter must include an `adr:` field pointing to the ADR it implements. A plan without an `adr:` link is invalid and should be rejected in review.

This rule is not stylistic — it enforces that decisions get recorded *before* execution starts, so scope drift, undocumented pivots, and "why did we do it this way?" archaeology are prevented at the source.

## Location and naming

- **Directory**: `plans/` at the project root.
- **Filename**: `NNNN-kebab-slug.md`. Monotonic sequence independent of the ADR sequence — one ADR can spawn multiple plans (phased rollout, follow-up work). Take the next number from history, not from the tree: plans leave `plans/` on completion or abandonment, so counting the directory repeats numbers. The next `NNNN` is one greater than the highest ever added under `plans/`:

  ```sh
  git log --all --diff-filter=A --name-only --format= -- plans/ \
    | grep -oE 'plans/[0-9]{4}' | sort | tail -1
  ```

  (The `adr` skill counts `ls docs/adr/` instead, and correctly, because ADRs stay in the tree.)
- **Cross-link**: frontmatter `adr:` field points to the ADR. The slug does not need to match the ADR's slug, though matching often reads well.

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

A plan's upstream is its ADR.

1. Begin the plan's branch (`git-workflow`), unless you are already
   on it with an unreviewed draft.
2. Run the review loop below. Round 1's draft is the introducing
   commit, with its `Derives-From` trailer.
3. A plan lands without a human. When a round raises an escalation,
   pause at that round's decision point. Commit its record, with each
   escalation and its reason under `Escalated:` and
   `Next: stopped for the human.`, then surface the escalations
   together and wait, before the next round or the landing. A plan
   review showing that the ADR needs revising is an escalation.
4. The human's answer is the human's decision. Record it in an empty
   commit titled `Record the human's answer on <path>`, whose body
   opens as "The record" below gives for the human's answer, and
   quotes it.
   It is part of round N's record. The loop then continues where it
   paused, under the stop rule; an answer does not restart it.
5. With no human available, stop and report at that decision point,
   after committing the record. Name each escalation and its reason,
   and say the plan has not landed.
6. Land (`git-workflow` `land`) only when the loop has stopped, any
   closing pass is committed, and no escalation is unanswered.

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

## Frontmatter

```yaml
---
title: <human-readable title, matches the H1>
status: draft
adr: 0001
date: YYYY-MM-DD
deferred_reason: null
---
```

- **status**: `draft` | `in-progress` | `deferred`. There is no `done` or `abandoned` status; both are expressed by removing the plan file (see "Status lifecycle").
- **adr**: required. The ADR number this plan implements (e.g. `0001`). If null, the plan is invalid.
- **date**: ISO date the plan was first written.
- **deferred_reason**: null unless `status: deferred`, in which case it must be a non-null string explaining what paused the work and what would unblock it.

## Status lifecycle

- **draft**: written but not yet started.
- **in-progress**: work is actively happening. Update as steps complete.
- **deferred**: paused, not abandoned. `deferred_reason` must be filled in. Anyone scanning `plans/` sees at a glance what's stalled and why. When resuming, flip back to `in-progress` and clear `deferred_reason`.
- **Completion** is not a status. It is expressed by deleting the plan file in the final commit on the last implementation branch. That commit carries this trailer, copied exactly:

  ```
  Completes: plans/NNNN-<slug>.md
  ```

  The value is the repository-relative path of the plan. The commit body says, in sentences, what the plan produced.
- **Abandonment** is not a status either. A plan whose work will not be done is deleted, and the deleting commit carries this trailer, copied exactly:

  ```
  Abandons: plans/NNNN-<slug>.md
  ```

  The commit body says, in sentences, why the work will not be done.

Both bodies are mandatory. Trailers carry the edge; the body carries the reason. Neither is optional.

Status updates ride with the code changes that reflect the new reality — e.g. flip `draft` → `in-progress` in the same commit as the first implementation change. Completion is the concrete case: the commit that deletes the plan file is the one that makes completion true. There is no status to flip first.

## The introducing commit

The first commit on the plan's branch carries this trailer, copied exactly:

```
Derives-From: docs/adr/NNNN-<slug>.md
```

A plan's direct upstream is its ADR, and the plan schema names exactly one (the `adr:` field). The trailer does not name the discovery note behind the ADR; that is one hop away through the ADR's own introducing commit.

## Body

After frontmatter and H1:

1. **Reference** — one-line link back to the ADR and any related plans.
2. **Steps** — ordered actions. Each step is executable and verifiable. Include which files change, what commands run, what commits get made. Steps that write or modify executable code, and steps that author a new skill, must be wrapped with the corresponding per-step directive block described under "Per-step directive wrappers" below.
3. **Verification** — how to prove the plan's outcome end-to-end (tests, smoke commands, manual checks).
4. **Progress notes** — a running log of what's actually happened, dates, blockers, decisions taken during execution that don't rise to the level of a new ADR. Optional but useful for `deferred` and `in-progress` plans.

## Per-step directive wrappers

Plans carry **no** top-of-plan directive. Wrappers are per-step, not per-plan.

There are two wrapper types. Both share the same shape: an instruction to the implementer, placed immediately above the step's text, worded so the block doubles as a description-matcher cue by echoing the target skill's own description phrasing. Both are boilerplate, not paraphrase — reproduce them verbatim.

Steps that carry neither wrapper — steps that neither write executable code nor author a new skill — carry **no** wrapper. Silent absence is the convention: do not add a negative assertion such as "this step does not need `test-first-workflow`" or "this step does not author a new skill". If a plan contains zero wrapped steps, it carries zero wrapper blocks. That is correct.

The directive lives in the artifact — not the skill body — so it survives context compaction and is re-read every time an implementer opens the plan.

### Wrapper for code-writing steps

Every plan step that **writes or modifies executable code** must be wrapped with the mandated boilerplate below. The wording echoes `test-first-workflow`'s own description phrasing ("write or modify executable code") so the block doubles as a description-matcher cue.

Mandated boilerplate:

```markdown
> **Directive for the implementer**: this step will write or modify executable code. Load the `test-first-workflow` skill before writing the code (docstrings → failing tests → code).
```

### Wrapper for skill-writing steps

Every plan step whose work is **authoring a new skill** — a new `skills/<name>/SKILL.md` artifact — must be wrapped with the mandated boilerplate below. The wording echoes `skill-forge`'s own description phrasing ("author a new skill") so the block doubles as a description-matcher cue.

Mandated boilerplate:

```markdown
> **Directive for the implementer**: this step will author a new skill. Load the `skill-forge` skill before writing the `SKILL.md` (frontmatter → failing eval scenario → skill body).
```

Edits to an existing skill body that do not change its `description` (its trigger contract) are **not** skill-writing steps in this sense; they carry no wrapper. Only the authoring of a new skill — or, equivalently, a change to an existing skill's `description` that retriggers the contract — takes this wrapper.

## What does NOT belong in a plan

- The decision itself, or the reasoning behind it. Those live in the ADR.
- Alternatives considered at decision time (ADR).
- Design trade-offs (ADR).

If while writing a plan you find yourself justifying *why* a choice was made, that's a signal the ADR is thin — suggest to the user that the ADR be amended, don't fold the reasoning into the plan.

## Do not

- Do not write a plan until its ADR is accepted; do not write the ADR unless asked.
- Do not leave a finished or abandoned plan in the tree.
- Do not edit the ADR from within the plan's commits. Cross-references only.
