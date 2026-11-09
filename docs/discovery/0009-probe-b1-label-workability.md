---
title: "Probe B1: are labels workable?"
status: in-progress
date: 2026-11-09
---

# Probe B1: are labels workable?

## Problem

Note 0002 §7.2 sets probe B1 as a paper exercise: take real task classes, design a harness for each, label it honestly, and count what the labels demand. Stop if most LLM outputs end up maximally tainted even with field-level labels and opaque handles, or if the human approvals per task make it unusable.

## Method

For each task:

1. **Fix the label lattice first**, so it cannot be bent to fit the answer.
2. **Design the harness the way you would actually want it**, at the level labels need: nodes, what each reads, what each branch decides on, sources and sinks, and the kind of each check (deterministic or model-as-judge; narrow field or free text). Prompts, schemas, `prep` internals and maximum tries are not needed.
3. **Propagate labels** by the rules in note 0002 §5: a deterministic node takes the join of its inputs; an LLM node takes the join of everything in its context, at best *model-generated* integrity; a checker's `Accept` can raise integrity on narrow fields, fully if the check is deterministic and weakly if it is model-as-judge.
4. **Check each sensitive point**: transitions (is the deciding value trusted enough?), sinks (is the content cleared for the destination?), and the lethal trifecta.
5. **Count twice**: once for the natural design, once after restructuring (quarantine, handles, field splits). The gap is the finding: how much restructuring the labels demand.
6. **Record the judgement calls** that decided the result.

**Lattice used:**
- Confidentiality: PUBLIC < OFFICIAL < OFFICIAL-SENSITIVE, plus a *personal data* flag.
- Integrity, high to low: user instruction > system-trusted > observed by deterministic code > model-generated > untrusted external.

## Task 1: drafting an ADR on how to QA spreadsheets

The harness takes input directly from a user. The user also supplies sensitive spreadsheets as examples and a list of their current QA processes. The output is an ADR committed to a repository.

**Sources and sink:**

| Source | Confidentiality | Integrity | Reasoning |
|---|---|---|---|
| S1 User's instructions | OFFICIAL | user instruction | the user's own words |
| S2 Example spreadsheets | OFFICIAL-SENSITIVE + personal | untrusted | supplied by the user, but cell contents could have been written by anyone; data, not instructions |
| S3 Current QA processes | OFFICIAL | user instruction | the user vouches for it (if colleagues wrote it, it is untrusted, which changes everything) |
| Sink: ADR committed to repo | repo cleared for OFFICIAL | — | ADRs are always accepted by a person |

### Pass 1: the natural design

D1 profiles the spreadsheets deterministically. L1 (LLM) works out the QA needs from S1, S3, D1 and raw spreadsheet samples. L2 (LLM) drafts the ADR from L1, S3 and the examples. L3 (LLM, model-as-judge) reviews it, and a branch on its verdict loops back to revise or goes on. A1 is the human accepting the ADR, and E1 commits it.

| Node | Output label | Sensitive point | Needs |
|---|---|---|---|
| D1 Profile (deterministic) | OFFICIAL-SENSITIVE + personal, untrusted (join) | — | — |
| L1 Understand needs (LLM) | OFFICIAL-SENSITIVE + personal, untrusted | — | — |
| L2 Draft ADR (LLM) | OFFICIAL-SENSITIVE + personal, untrusted | — | — |
| L3 Review (LLM judge) | `{verdict, findings}`, OFFICIAL-SENSITIVE, untrusted | `verdict` drives a branch | weak endorsement; injected cell text is in the context that decides the branch |
| A1 Human accepts | — | approval | exists anyway |
| E1 Commit | — | sink cleared for OFFICIAL | declassify OFFICIAL-SENSITIVE to OFFICIAL; only a human can, because free prose may quote the data |
| Trifecta | | E1 holds sensitive data, untrusted content and a way out | broken only by A1 coming before E1 |

**Counts:** 1 weak endorsement per review round, exposed to injection; 1 declassification and 1 approval, combinable into the acceptance step; 3 of 4 nodes maximally tainted.

**Verdict:** a technical pass, because the acceptance step that exists anyway absorbs the declassification. A poor pass: the accepting person must hunt the ADR for leaked spreadsheet data as well as judge the decision, and spreadsheet contents can steer the review loop.

### Pass 2: restructured

Raw spreadsheet content reaches only one LLM node, which has no capabilities, and only narrow, checkable facts leave it.

| Node | Reads | Output label | Change |
|---|---|---|---|
| Q1 Quarantined describer (LLM, no capabilities) | D1 and samples | list of `{check_type: enum, sheet: handle, column: handle, evidence: int}`, OFFICIAL-SENSITIVE, untrusted | the only node that sees raw data; it can answer only in enums, handles and numbers |
| N1 Endorse (deterministic) | Q1 | enum, handle and int fields raised to observed | full endorsement: valid schema, handles resolve to real sheets and columns |
| X1 Declassify by aggregation (deterministic) | N1 | counts per check type, OFFICIAL | no free text released |
| L2 Draft ADR (LLM) | S1, S3, X1 | OFFICIAL, model-generated | never sees the spreadsheets |
| L3 Review (deterministic template check + LLM judge) | draft | verdict weakly endorsed | quality is still model-judged, but no untrusted content can steer it |
| A1, E1 | | OFFICIAL into an OFFICIAL repo | no declassification at the sink |

**Counts:** 1 full endorsement; 1 weak endorsement per round, no longer exposed to injection; 1 automated declassification (or 1 human one if policy demands it); 1 approval, the acceptance that exists anyway; 1 node maximally tainted, with no capabilities.

### Findings from task 1

- **Labels did not block the task; they reshaped it.** Restructuring cost three small nodes (Q1, N1, X1). In return, the accepting person no longer hunts for leaked data, and spreadsheet contents cannot steer the review loop.
- **The cost moved to performance.** In pass 2 the drafter sees a summary of check types, not real examples, so it may write a vaguer ADR. B1 cannot measure this; it is a question for B2/B3, so this task should join B2's task set.
- **Four judgement calls decided the result:** how far the QA process list is trusted; whether spreadsheet cells count as untrusted; what the repository is cleared for; and whether automated declassification by aggregation is allowed, or note 0002 §5's example policy ("declassification from level X requires a human approval node") applies.
- **A gap in note 0002's vocabulary.** X1 needs a declassification rule that can be checked mechanically ("aggregate counts, no free text"). Note 0002 does not yet say how a deterministic `declassify` declares what it may release, so that the checker can verify it.
- **Pass 1 is the natural design and is the one most people would build.** The labels' value showed up only on comparing the two passes, which supports counting twice.

## Open questions

- How does a deterministic `declassify` declare its release rule, and how does the checker verify it? (For note 0002.)
- Is automated declassification by aggregation acceptable, or does every declassification from OFFICIAL-SENSITIVE need a person?
- Does withholding raw examples from the drafter degrade the ADR? (For B2/B3.)
- Does B1 hold for tasks whose output must contain sensitive content? Task 2 tests this.

## Next steps

- Task 2: drafting a QA report on a specific spreadsheet, a task expected to fail because sensitive content must reach the output.
- Add the declassification-rule gap to note 0002.
- Carry task 1's two passes into B2's task set.
