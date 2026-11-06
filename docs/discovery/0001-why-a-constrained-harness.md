---
title: "Why build a constrained harness: assurance, and the benefit to the organisation"
status: in-progress
date: 2026-11-03
---

# Why build a constrained harness: assurance, and the benefit to the organisation

> **Imported from myelin, 2026-11-06.** Copied from `communitiesuk/myelin` issue #156 (body as of this date). It is a copy, not a link: eshr does not depend on myelin's files. References to ADRs, issues (`#NN`), plans, skills and `[[...]]` backlog items are to myelin's, kept as provenance. Note numbers differ: myelin's discovery notes 0003, 0005 and 0006 are eshr's 0003, 0004 and 0002.

## Seed

Raised 2026-11-03, before Phase 3 of the roadmap (#80) begins. Phase 3 is the orchestration "how" (#79). The maintainer wants the **reasons for building the harness**, and how they turn into **benefit for the organisation**, set out before that work starts. This seed captures the thinking so far. **No decisions on scope or architecture are made here.**

## The lead reason: assurance

Harnesses as they are usually understood are **unconstrained**: a loop in which the model picks which tools to use, uses them, and decides for itself when to stop and respond. The harness shape discussed in `docs/discovery/0003-escalation-and-orchestration.md` (entry dated 2026-10-27) is **constrained**: one call over recorded, assembled context, with the output checked straight away. Chaining calls together makes it unconstrained again, trivially, but it can be kept constrained if we choose to.

The maintainer's concern: **in a government context, it may always be a problem to have an unconstrained agent running in a sensitive environment.**

What matters is **who holds the control flow**, not the number of calls:

- **Unconstrained (model-led loop).** The model chooses the actions, their order and when to stop. The only limit on what can happen is the set of tools it has. It can be assured only by containment (sandbox, permissions) and review afterwards.
- **Constrained (engine-led DAG).** A deterministic engine over a declared DAG holds the control flow. The model only fills in content at a node, and its output is checked before anything consumes it. It can be assured **by design**, through properties stated in advance:
  1. *Enumerable behaviour.* The DAG specifies everything that can happen.
  2. *A complete record.* Each node's assembled input and its output are logged, so runs can be audited and replayed.
  3. *Bounded authority.* LLM nodes have no tools. Side effects happen only in deterministic action nodes, which are ordinary code that can be reviewed and tested.
  4. *Oversight by structure.* Escalation is the engine exiting with nothing ready, so humans come in at named points in the DAG.
  5. *A smaller blast radius for prompt injection.* Injected text can affect only an output that is then checked. It cannot steer tool calls.

A stronger way to put the claim than "always problematic": **an unconstrained agent can be assured only by containment and review afterwards; a constrained one can be assured by design.** Whether a contained loop is acceptable then becomes a risk-appetite call for each environment.

### Where the argument needs care (open, not decided)

- **The constraint has to be enforced, not merely a convention.** The keystone rule from 10-27 ("a worker is one LLM call or one deterministic action") counts as an assurance property only if the engine enforces it: tool-less LLM calls, a declared DAG, undeclared edges refused.
- **The falsifier needs a policy.** The 10-27 entry says the first task that genuinely resists decomposition breaks the rule. The assurance story needs a sanctioned exception for that case (for example a loop that runs only inside a container and shows in the record), or exceptions will happen quietly.
- **Action nodes that run model output are hot spots.** Running LLM-written code (for example tests on a generated implementation) brings unconstrained behaviour back in at one remove.
- **Scope.** The interlocutor is a loop, and myelin is itself built in a loop harness. Is the claim about agents running *in* sensitive environments (live data, production systems), about what they *produce* (policy, decisions that affect the public), or both? Should the interlocutor stay a loop, with the human as its constraint?

## Further reasons, and the benefit each could bring

Most of the earlier list turns out to be aspects of assurance:

| Reason (evidence on record) | Benefit to the organisation |
|---|---|
| **Reliability currently depends on a watchful human.** In the Phase 2 stage-review runs, every breach was a handover or context-assembly failure, caught live by the parent or the human (0003, 2026-10-27). | Quality that does not depend on who is driving. Fewer errors that look plausible but are wrong. |
| **Escalation has no mechanism.** The four "needs a human" triggers (0003) fire partway through the work. The harness permission gate matches command patterns and has been observed behaving non-deterministically. | Clear lines between human decisions and agent work, enforced rather than hoped for. Defensible accountability for work done with AI help. |
| **No run record.** Stage-review evidence exists only in commit bodies. | The ability to say what the AI did, why, and how often a human stepped in, for audit, assurance and reporting on AI use. Evidence for improving the tooling. |
| **Cost.** myelin's founding thesis is that work further right runs on cheaper models. Single-turn workers and a mostly deterministic orchestrator are how that happens. | Lower cost per artefact, with frontier-model spend kept for the stages that need judgement. |
| **Human attention is the bottleneck.** Parallelism is the later payoff, once handover is self-contained. | More work directed per person. |
| **Harness neutrality** (the Codex check; an adapter layer). | Less vendor lock-in, more room to move on procurement. |

## Honest counterweights

- **The bet concentrates risk in the context assembler** (`docs/discovery/0005-compression-and-handover.md`). If the assembler doesn't work, the reliability, cost and capacity benefits don't either.
- **The counterfactual isn't "do nothing".** The alternatives are (a) harden the skills-only version, which Phase 2.5 is already doing, or (b) use the harness's built-in orchestration (#78). The assurance argument answers (b), because built-in orchestration is model-led and so unconstrained. (a) still needs an answer.
- **Adoption cost.** The skills version is gaining traction in the organisation, and a harness may raise the bar to entry.

## Questions to explore

- Who is this case for: the maintainer, aaai leadership, or adopting teams? The framing differs for each.
- What evidence would show the harness was worth it? Candidates: breaches per artefact with no human catch, the share of stages run on a cheaper model, human interventions per run.
- How does the assurance argument line up with existing government guidance on AI assurance and transparency? Worth checking rather than assuming.
- Does the assurance principle deserve an ADR of its own, which the harness ADRs would derive from, rather than living as a justification inside one?

## Related

- `docs/discovery/0003-escalation-and-orchestration.md`, especially the entry dated 2026-10-27 (the single-turn primitive and keystone rule)
- `docs/discovery/0005-compression-and-handover.md` (the context assembler)
- #79 (orchestration "how"), #78 (harness inventory), #80 (roadmap), #131 (roadmap gap)
