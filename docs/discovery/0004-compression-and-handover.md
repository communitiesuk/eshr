---
title: How should context pass between orchestrated agent steps?
status: in-progress
date: 2026-10-26
---


# How should context pass between orchestrated agent steps?

> **Imported from myelin, 2026-11-06.** Copied from `communitiesuk/myelin` `docs/discovery/0005-compression-and-handover.md` at `4507d27`. It is a copy, not a link: eshr does not depend on myelin's files. References to ADRs, issues (`#NN`), plans, skills and `[[...]]` backlog items are to myelin's, kept as provenance. Note numbers differ: myelin's discovery notes 0003, 0005 and 0006 are eshr's 0003, 0004 and 0002.

## Where this sits

`docs/discovery/0003-escalation-and-orchestration.md` is the *control
plane* of the orchestrator turn: *when* work needs a human, *who*
supervises a worker, how a block is imposed and resolved. This note is
the *data plane* of the same turn: *what* passes between steps and how
it is represented, compressed, logged and measured.

They meet at a specific seam. D0003's interlocutor hands a worker "the
relevant skills" and its probe 1 asks whether a worker reliably loads
them; this note reframes skills as the **codebook** and the **context
assembler** as the thing that selects, binds and hands them over — a
candidate mechanism for exactly that handover. D0003's enforcement
piece needs "somewhere to read a verdict from"; this note's per-handover
**log record with a link to the outcome** is that substrate. And the
stage-review loop that D0003 names as the first step (#77) —
drafter → reviewer → parent — *is* a handover chain this note would
govern, and so the smallest place to test these ideas on real work.

This note is not close to a decision. It records a developed line of
thinking so the "how" ADRs (#79) can draw on it.

---

Design notes on passing context between agent steps.

## The problem

Multi-step agent workflows face a tension:

- **Handing over** between steps risks dropping detail that matters later.
- **Not handing over** lets context grow until important instructions are missed or ignored.

"Long-running" here means many independent turns, not wall-clock time. Each extra turn is another chance to go down a self-made rabbit hole, put 2 and 2 together and make 5, and act on it.

## Framing: handover as compression

Following the simplicity principle in cognitive science (Chater & Vitányi, 2003), treat a handover as a **two-part code** in the minimum-description-length (MDL) sense:

1. **Model**: the general pattern this case is an instance of.
2. **Residual**: how this case departs from the pattern.

A good handover is short because the receiver already holds the model. It is faithful because the residual is carried explicitly.

Code length is always relative to the decoder. Compression only works if the sender and receiver share the codebook.

## Where the codebook lives

The codebook is **not** the LLM's training prior. It is explicit and lives in the harness: skills, schemas, and files in the repo.

- The LLM **applies** the codebook: it encodes, decodes, and chooses which pattern fits.
- The harness **owns** the codebook, and the codebook is versioned, inspectable and auditable.
- Designing the workflow in advance means building the codebook in advance. Each step's output schema is shared structure that never needs re-sending.

This avoids a key failure of implicit compression. When an LLM summarises freely, it compresses toward its own prior: it regresses to the typical case and drops the odd detail. An implicit codebook you don't control is also one you can't audit.

## Continuous recompression

The codebook is not append-only. Patterns can be added, edited, merged or removed as easily as they are introduced, and the system keeps trying to compress itself further in the light of new data.

**Objective:** minimise, over the whole history,

```
L(codebook) + Σ L(handover | codebook)
```

**Typical moves:**

- **Promote**: a recurring exception moves from the residual into the codebook.
- **Merge or abstract**: overlapping patterns are factored into shared, more abstract ones.
- **Retire**: a pattern is deleted when it costs more to carry than it saves.

**Admission rule:** a pattern earns its place when it shortens enough future handovers to pay for its own length.

## What continuous recompression requires

1. **A retained corpus.** Keep the raw episodes, residuals included. You can only judge whether a recompressed codebook is better by re-encoding the history it is meant to explain. Without the corpus, recompression degrades into rewriting by taste, which reintroduces the model's prior through the back door.

2. **Recompression as migration, with a decoding test.** A codebook change is valid only if past handovers still decode to the same meaning (or better). This one check is:
   - the acceptance test for a proposed change;
   - the guard against version skew;
   - the audit record of why the codebook changed.

   Anything may propose a change; a check against fixed criteria decides.

3. **Consequence weighting.** Pure MDL will merge two patterns that differ only in a rare detail, because rare details are cheap in description length. But a rare, critical exception is exactly what you can't afford to lose. Description length can't supply this weighting. Some cases must be marked, from outside the compression objective, as expensive to get wrong. "Risky" is not a property the system can detect for itself: every action has consequences.

4. **Versioning and snapshots.** A handover is only decodable with the codebook it was encoded under. Stamp each handover with the codebook version. A continuously changing codebook means behaviour changes over time, so answering "why did it do X on date D?" requires the codebook as it was then.

## The context assembler

The decoder made explicit: a single choke point through which every handover passes. It has three jobs in one component:

1. **Assembly**: build the next step's context from the codebook.
2. **Observation**: log how the codebook is used in practice; these logs *are* the retained corpus.
3. **Testing**: replay logged inputs under a candidate codebook. This is the decoding test.

### Per call

1. Take the next step's spec and the previous step's output.
2. Select the codebook entries whose stated conditions match.
3. Bind each entry's parameters.
4. Attach the residual and pointers to raw sources.
5. Emit the assembled context and a log record.

### Computing the residual

Don't rely on the upstream agent to decide what is residual: it can't flag what it didn't notice. **Compute it** instead. The residual is whatever in the output the selected schemas don't account for, found with a structural diff, not a judgement call. The upstream step can add deviations it noticed, but the computed diff is the floor.

### Selection mechanism

Use deterministic matching on typed fields wherever possible, because it is reproducible and auditable. Use LLM-based selection only where matching is genuinely fuzzy, and log which mechanism made each choice.

### Log record

- step ID and codebook version
- entries selected, with the match evidence for each
- entries considered and rejected
- parameters bound
- the residual, verbatim
- pointers provided
- token cost
- **a link to the outcome**: without it the log records usage but not whether the usage was good

### Signals for recompression

| Signal | Suggests |
|---|---|
| The same residual recurs across cases | Promote it into the codebook |
| Pointers are often followed back to source | The handover is too lossy for that step |
| Entries are loaded but never used downstream | Narrow or retire them |
| Failures track one particular entry | A bad pattern or a bad match condition |

## Measuring compression

Compression is only valuable if the output is at least as good as the uncompressed version. The assembler therefore measures both **how much** each codebook entry compresses and **whether** the compressed context performs as well.

### Two assemblies

For each handover, the assembler computes:

1. **With the playbook**: codebook entries, their parameters, the residual and pointers.
2. **Without the playbook**: the raw context (the full upstream output plus sources).

The second is the baseline that compression is measured against.

### Compression per entry

The structural diff that computes the residual already divides the upstream output into spans, each either accounted for by an entry or left as residual. So for each entry used, log:

- **tokens accounted for**: the length of the raw content that entry explains;
- **tokens used**: the reference to the entry plus its parameters;
- **saving**: tokens accounted for minus tokens used.

**Net value of an entry** = the sum of its savings across uses, minus its own length each time it is loaded. This is the admission and retirement rule, computed from logs rather than estimated.

**Savings don't add up across entries.** Entries overlap, so individual savings won't sum to the total difference between the two assemblies. For honest attribution, compute each entry's contribution by leaving it out and re-assembling. This is text assembly only, with no model call, so it is cheap enough to run on every handover.

### Fidelity

Size alone is meaningless: an entry that discards everything "compresses" perfectly. On a **sample** of handovers, run the next step on both assemblies and compare:

- the outcome (task success, validator results);
- turns to converge.

Sample because this costs model calls; leave-one-out attribution is cheap, fidelity checks are not.

### What the comparison tests

The baseline is not neutral: it *is* long context, with its failure modes.

- If the playbook version **matches** the raw version with fewer tokens, the codebook is saving space.
- If it **beats** the raw version, the codebook is doing what the design claims: protecting the next step from details getting lost in a long context.
- If it **underperforms**, the codebook is losing information that matters. Trace the shortfall to particular entries using the leave-one-out results and the per-turn corrections.

Over time this comparison is the empirical test of the whole approach, not just a cost metric.

### Extra log fields

- raw tokens, assembled tokens, residual tokens
- per entry: tokens accounted for, tokens used, leave-one-out difference
- for sampled cases: outcome and turns to converge for both assemblies

## Per-turn recording

Recording must happen **every turn**, not just at the end of a step. A multi-turn agent can partly correct its own bad output, so a pattern that was misapplied and then fixed ends in a good outcome. If you log only final outputs, the wrong codebook entry gets the credit. The correction path is where the information is.

- **Corrections are residual.** The difference between the first attempt and the final output is information the codebook should have supplied and didn't. If the same fix recurs, it is a candidate for promotion.
- **Turns to converge is a cost.** Correction turns are part of what a pattern really costs and belong in the MDL total. An entry that reliably needs several fixing turns is worse than its description length suggests.
- **Attribution.** With each turn logged alongside the context it was given, a correction can be traced to its likely cause: a wrong match, a missing entry, or residual that wasn't passed on.
- **Log what triggered each correction.** A correction prompted by an external signal (a failed test, a validation check, a tool error) is strong evidence. A self-prompted correction is weaker, because agents sometimes "correct" toward the wrong answer or talk themselves into a plausible but wrong revision. Weight the two differently when deciding what to promote.

### Assembly per turn

Once the assembler is in the turn loop, it can **rebuild the agent's context each turn** from the codebook, the current parameters and the residual so far. Each turn then becomes a handover from the agent to its next self. That controls context growth within a step using the same mechanism as between steps: one solution to both the handover problem and the long-context problem.

The cost is log volume. Store each turn as a structured difference from the previous one, not a full transcript.

## Remaining failure points

- **Pattern matching.** The model still chooses which pattern applies, and this is where errors concentrate. A strong simplicity prior trades variance for bias: it fails by confidently applying the right pattern to the wrong situation. Mitigation: each skill states the conditions under which it applies, and the harness logs which pattern was chosen, so a mismatch shows up in the trace as a specific wrong choice.
- **Codebook load.** Every entry is text that may need loading, so the long-context problem can reappear at the codebook level. Mitigations: load a skill only when it matches; retire entries actively.
- **Propagated errors.** One bad generalisation written into the codebook is inherited by every later handover. A local 2+2=5 becomes systemic, and the same route lets injected content persist (memory poisoning). Mitigation: gate codebook writes with the decoding test and/or human review.

## Relevance over simplicity

Simplicity measures structure, not relevance. The better objective is closer to the **information bottleneck** (Tishby et al., 1999): compress the input while keeping what predicts the next step's needs. That is normally hard to compute, but a workflow designed in advance makes it tractable, because each step's needs are known.

## Handover checklist

A handover artefact should contain:

- [ ] **Schema reference and codebook version**: the model part, plus which version of it.
- [ ] **Parameters**: the instance-specific values the schema calls for.
- [ ] **Explicit deviations/exceptions field**: a protected place for the residual so it can't be summarised away.
- [ ] **Pointers to raw sources**, not copies: lossless compression by reference, so the receiver can retrieve detail on demand.
- [ ] **Which pattern(s) were applied**: logged for audit.

And it should pass a **decoding test**: using only the handover, can the receiving step answer the questions its task will put to it?

## Summary

Compression resolves the handover-versus-long-context tension when:

1. the codebook is explicit and lives in the harness;
2. the residual is protected;
3. recompression is continuous but gated by a decoding test against a retained corpus;
4. consequence weighting is supplied from outside the compression objective;
5. a context assembler mediates every handover, including turn-to-turn within a step, and logs each one with its outcome;
6. compression is measured against an uncompressed baseline, and kept only where the output is at least as good.

Leave any of these to the model's own sense of what is simple, and you get the failure you were trying to avoid.

## [2026-10-27] Single-turn workers collapse the per-turn problem

Worked through with the maintainer alongside `0003`'s [2026-10-27]
single-turn primitive. That control-plane move reshapes this note's
hardest machinery.

**The per-turn apparatus dissolves.** "Per-turn recording" and "assembly
per turn" exist to tame the *intra-step* turns of a multi-turn agent:
log every turn because a multi-turn agent can correct its own bad output
and miscredit the codebook. If a worker is a **single turn** (`0003`'s
keystone rule), there are no intra-step turns. Turn = step = handover,
so the per-turn corpus this note wants is the per-handover corpus the CA
already emits — for free, at one granularity. The open question above
("whether 'rebuild context every turn' is feasible on this harness or
only between steps") does not get answered; it **ceases to exist**. The
assembler lives purely *between* workers — the easy, portable case.

**The correction path moves into the DAG.** This note says "the
correction path is where the information is." Under single-turn workers
it does not vanish — it becomes a *downstream node* (reviewer → reviser),
each a logged handover. Corrections become structural and auditable
(a node, an edge) rather than buried in an agent's self-talk, which is
strictly better for the retained corpus. The drafter → reviewer → reviser
chain the Phase 2 runs already exercised is this shape.

**But the CA becomes load-bearing for both planes.** A worker's
assembled input is bounded; a single-turn *orchestrator*'s input is the
run-state — the history so far — which must be compressed to fit one
turn. That is this note's hardest job (codebook + residual over the
whole trajectory). So pushing orchestrators to one turn *raises* the
stakes on the CA; it does not lower them. The risk concentrates in one
inspectable, testable component rather than smearing across long-lived
agents.

**Why that concentration is survivable.** The CA's selection problem is
bounded by myelin's own thesis: myelin aligns the repository on intent,
so the corpus is *pre-curated* — the repo is meant to hold only useful
context. The CA is not summarising arbitrary sprawl; it selects the most
relevant entries for a *well-specified* task. That is the condition this
note already names as making the information-bottleneck tractable
("a workflow designed in advance makes it tractable, because each step's
needs are known"), tightened further by the pre-curated corpus. The
commitment is to use the CA until it works, with its own logs as the
iteration mechanism — and to build its enabling skills (history,
revision) only *just good enough* to get there, rather than guessing
their shape ahead of the evidence.

**Contracts give the typed fields a home.** This note wants
"deterministic matching on typed fields wherever possible." `0003`'s
workers define their input/output contracts *internally* and validate
incoming context at their own door, so the schemas the CA matches on are
owned by the workers, not declared separately.

## Relationship to D0003 and open threads

- **Codebook ≈ skills (probe 1).** If the codebook *is* the skill set and the assembler hands it over deterministically, D0003's probe 1 ("does delegating to a worker make skill-use reliable?") partly reframes: the question becomes whether deterministic selection + a protected residual make skill-loading reliable where a bare "use git-workflow" prompt does not. Still unmeasured.
- **Log record ≈ verdict substrate.** The per-handover log with a link to the outcome is a candidate for the "somewhere to read a verdict from" that D0003's enforcement piece lacks.
- **Stage reviews (#77) as the first testbed.** The drafter → reviewer → parent handover is the smallest real handover chain; its logs would be the first corpus.
- **Consequence weighting ↔ blast radius.** Point 3's "expensive to get wrong, supplied from outside" is the same signal D0003 routes to a container + `PreToolUse` hook for its trigger (2). The two notes should share one definition of consequence rather than grow two.
- **Open:** what is the concrete schema of a codebook entry and of a handover artefact; where the assembler lives relative to the harness's own context management; and ~~whether "rebuild context every turn" is feasible on this harness or only between steps~~ — the last is dissolved by the [2026-10-27] entry: single-turn workers make the assembler live purely between steps, so rebuild-every-turn is never needed.

## Candidate seeds — only once a "how" ADR exists

Developed, buildable slices that should become `seed` issues (or plan steps) *after* the governing ADR is decided, not before — listed here so they aren't lost:

- A context-assembler component with the five-step per-call contract.
- Codebook-version stamping on every handover artefact.
- The structural-diff residual computation and leave-one-out saving metric.
- The decoding-test harness that replays a retained corpus under a candidate codebook.
- Per-turn structured-diff logging in the agent turn loop.

## References

- Chater, N. & Vitányi, P. (2003). Simplicity: a unifying principle in cognitive science? *Trends in Cognitive Sciences*, 7(1), 19–22.
- Tishby, N., Pereira, F. C. & Bialek, W. (1999). The information bottleneck method. *Proc. 37th Allerton Conference*.
</content>
</invoke>
