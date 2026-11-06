---
title: Constrained agent harnesses — design notes
status: in-progress
date: 2026-11-06
---


# Constrained Agent Harnesses: Design Notes

> **Imported from myelin, 2026-11-06.** Copied from `communitiesuk/myelin` `docs/discovery/0006-constrained-harness-design-notes.md` at `7bf4128` (never merged into myelin; eshr is its home). It is a copy, not a link: eshr does not depend on myelin's files. References to ADRs, issues (`#NN`), plans, skills and `[[...]]` backlog items are to myelin's, kept as provenance. Note numbers differ: myelin's discovery notes 0003, 0005 and 0006 are eshr's 0003, 0004 and 0002.

*Status: exploratory design thinking, not a specification. Captured from a design discussion, November 2026.*

> **How to read this note (maintainer, 2026-11-06).**
>
> - **Ideas, not requirements.** The assurance mechanisms here (sealed node types, data labels, static policies, endorse/declassify, and so on) describe *what can be done*, not an upfront list of what must be built. Choose them when a real need calls for them.
> - **Exactly one call per primitive.** "Agentic nodes as bounded LLM loops" (§3, §4.3) came in from the literature, not from the maintainer's preference. The intended shape is §6's prepare → call → check: each primitive makes exactly one call, and the loop belongs to the primitive, not the model. Where §3 or §4.3 says otherwise, §6 wins.

## 1. Problem

Current coding-agent harnesses (Claude Code, Codex and similar) use an **open loop**: the model decides which tool to call next and when to stop. Constraints are added from outside, through permission modes, sandboxes and hooks, but the model owns the control flow.

Two motivating problems:

1. **Behavioural guarantees.** It is hard to make an open-loop agent reliably keep a repository consistent with the user's *current* intention. Intentions change during a session, superseded instructions stay in the transcript and compete with current ones, and obligations such as "always update tests and docs to match" are only best effort.
2. **Deployability in conservative, sensitive-data organisations** (for example government). Assurance processes assume behaviour and data flows can be enumerated in advance. Open-loop agents decide their flows at run time, so they cannot be assessed in those terms.

**Working hypothesis:** a harness that owns the control flow and manages context, with the model used only where a transformer is actually needed, will be both *more assessable* and *better performing*, because each model call gets a cleaner context.

## 2. Key distinction: what guards can and cannot enforce

From Schneider, *Enforceable Security Policies* (2000): an execution monitor can enforce **safety properties** ("nothing bad happens") but not **liveness properties** ("something good eventually happens").

Applied to an open-loop agent:

| Requirement | Kind | Enforceable in an open loop? |
|---|---|---|
| "Never push to main", "no network" | Safety | Yes, **if** enforced at the level of effect (capabilities, sandbox, network policy). Not if enforced by matching command strings: the same effect can be reached by equivalent means, and deciding equivalence is undecidable in general. |
| "No commit until tests have run" | Safety (ordering) | Yes, by gating the later action on having observed the earlier one. |
| "Must run the tests" / "must update docs" | Liveness (obligation) | **No.** The best available is gating termination on evidence, which invites gaming: running an empty test filter, weakening assertions, looping until the budget runs out. |
| "Must do a good review" | Quality judgement | No. |

**Conclusion:** an open loop with hard, effect-level guards can reliably enforce *prohibitions and orderings*. *Obligations* can only be guaranteed by **owning the control flow**: the step happens because code calls it, not because the model chose to.

Other observations:
- A guard log records what was blocked, not what the model intended.
- A blocked agent improvises workarounds, so its behaviour after a block is unpredictable.

## 3. Hybrid graphs

A **hybrid graph** is a harness whose top-level structure is a state machine written as code or a spec.

- **Deterministic nodes**: plain code (branch, lint, test, check diff scope, open PR). Their outputs are *facts*.
- **Agentic nodes**: bounded LLM loops with code-fixed boundaries: a tool set, curated starting context, a budget, and an output contract (schema).
- **Edges**: transitions owned by code. A model may at most choose from a fixed, enumerated set of branches.

Guarantees hold **at node boundaries**. *Inside* an agentic node you are back to the open-loop regime, with guards for prohibitions and best effort for obligations. The design skill is cutting the graph so everything that must be guaranteed sits on a boundary or in a deterministic node.

The two extremes are degenerate cases: a pure workflow (Agentless is close to this) is all deterministic or single-call nodes; Claude Code out of the box is a single agentic node that owns everything, including termination.

Production precedent: Stripe's "Minions" use **blueprints** that interleave deterministic nodes (lint, CI, push) with agentic loops, for unattended runs, with CI retries capped at 2.

## 4. Proposal: a spec-interpreting harness runtime

A **runtime that interprets a declarative spec for a hybrid graph.**

- The **spec is the assessment artefact.** Security teams review specs against policy.
- The **runtime is the reference monitor**, assured once.
- Analogy: AWS Step Functions (declarative state machine plus managed runtime), with a security model added to the spec language.
- Build on an existing durable-execution engine (such as Temporal) rather than writing a new scheduler. The novel parts are the **type and label system and the static policy checker**.

### 4.1 What the spec declares

Per node:
- **type** (see 4.3)
- **capabilities**: tools, credentials, network egress, filesystem scope
- **data labels** it may read, and labels on its outputs
- for agentic nodes: model, budget, output schema

Per edge: a transition condition evaluated by code.

### 4.2 What the runtime enforces

- Each node runs with only its declared capabilities, enforced **at the level of effect**: scoped credentials, sandbox, network policy.
- Output schema validation, budgets, ownership of transitions.
- A trace that provably follows a path through the declared graph.

### 4.3 Node types: a small, closed, sealed set

| Type | Behaviour | Label rule |
|---|---|---|
| `deterministic` | runs a referenced, versioned function | propagate only (join of inputs) |
| `agentic` | bounded model loop | output = join of everything in context |
| `endorse` | runs a referenced validator | may **raise integrity**, only for outputs matching a declared *narrow* schema |
| `declassify` | redaction, aggregation, or human release | may **lower confidentiality** |
| `approval` | human gate | — |
| `egress` | the only exit from the system, governed by allow-lists | — |

**Being a first-class node type matters.** Relaxing a label is *syntax*, not convention, so the checker can list every point where trust is raised or sensitivity lowered, and enforce policy on them. This is the same idea as Rust's `unsafe` and Jif's `declassify` / `endorse` keywords.

**Extension is by composition, not inheritance.** Each type has *slots* (function, validator, prompt, tools) for user code. Slot fillers run **inside** the node: the node acts as host and monitor, starting the filler with declared capabilities, validating its output, applying the type's label rule, and handing results to the transition logic. Fillers cannot alter the type's semantics. Subclassing is ruled out because it would allow overriding them.

- New *behaviour* means writing a function for an existing slot: cheap, everyday, checked by policy.
- A new *kind* of node means changing the runtime: rare, and goes through the runtime's own assurance.

### 4.4 Nesting

A slot may be filled by another node or subgraph. Useful cases:
- An agentic node whose **tools are first-class nodes** (an egress node with allow-list; a quarantined agentic node returning opaque handles). This is the CaMeL structure expressed as a spec.
- A subgraph of deterministic checks used as an endorse node's validator.

**Rule: the outer type bounds the inner.**
- Capabilities only shrink.
- Labels follow the more pessimistic rule. A "deterministic" node containing an agentic slot must be rejected, or retyped as agentic.
- An `endorse` node whose validator is an agentic node is **model-as-judge**. Forbid it, or label it as a *weak endorsement* class that downstream policy can treat differently.
- **Every nested structure must flatten.** Policies run on the flattened graph, so nesting is an authoring convenience with no new semantics.

## 5. Data labels (information flow control)

Every value crossing an edge carries a label **assigned by the runtime**, never self-declared by a node. Anything unlabelled is treated as the most restrictive case.

**Two independent axes:**
- **Confidentiality**: who may see the value. Map it to the existing classification scheme (for example OFFICIAL, OFFICIAL-SENSITIVE) plus flags such as personal data. Governs **exfiltration**.
- **Integrity / provenance**: user instruction, system-trusted, observed by a deterministic node, model-generated, untrusted external. Governs **injection**.

Combining inputs raises confidentiality and lowers integrity (the **join** rule).

**The "lethal trifecta"** (Willison: private data, untrusted content, exfiltration channel) becomes a graph check: no node simultaneously holds high-confidentiality inputs, low-integrity inputs and an outbound capability.

**LLM nodes mix every label in their context.** Any output token may depend on any input token, so the output takes the join of the whole context. This causes **label creep**. Mitigations:
- **Context minimisation**: everything a node sees taints its output.
- **Opaque references** (CaMeL): pass handles, not content, so privileged nodes can route data without being contaminated.
- **Quarantined nodes** with no capabilities and constrained outputs for processing untrusted content.

**Other rules:**
- **Narrow channels:** a validator turning free text into an allow-listed enum or boolean leaves little room for an injection to pass through.
- **Label fields, not messages.** In `{decision: enum, rationale: text}`, `decision` can be endorsed while `rationale` stays tainted and can never drive a transition.
- **Observed vs asserted:** tag whether a value was observed (test result, database read) or asserted by a model. Unverifiable claims then cannot pass as facts.
- **Keep the lattice small:** a handful of confidentiality levels and 4–5 integrity classes, plus personal-data flags.

**Static policies, checked in CI on every spec change, for example:**
- No node holds all three legs of the trifecta.
- Every path to an outbound or irreversible action passes through approval or allow-list.
- Untrusted-labelled data never reaches a node that chooses transitions.
- All loops are bounded, so every run terminates.
- Declassification from level X requires a human approval node.

**Assessment attaches to the node contract** (capabilities, labels, schema), **not the implementation.** Model, prompt or budget can change inside a node without reassessment. Contract changes produce a spec diff that triggers a policy re-check and review.

## 6. The core primitive: prepare → call → check

A single uniform primitive:

```
P ::= f                                              -- atomic: plain function
    | ⟨ prep: P, call: C, check: P, budget, escape ⟩ -- composite
```

- **prep**: a nested primitive that builds the input for the call (context selection, labelling).
- **call**: exactly **one** tool call: deterministic code *or* an LLM API call.
- **check**: a nested primitive that evaluates the result. On failure, loop back to prep (within budget) or leave via the **escape** edge.

This is essentially a Hoare triple `{prep} call {check}` with retry. Every model invocation sits between preparation and a check. **The loop belongs to the primitive, not the model.** Agent-like behaviour comes from composing primitives.

Design rules:
1. **Ground the recursion:** a primitive whose slots hold plain functions is the base case. Nest only where preparation or checking needs a model.
2. **The call is the only effect.** prep and check, including anything nested in them, hold read-only capabilities. Every side effect then has one declared call site per primitive.
3. **The loop-back is a channel.** Feedback from check to prep can carry taint. Either propagate labels honestly (later attempts run at lower integrity), or **narrow the channel**: structured failure reasons (enum plus deterministic diagnostics), not raw model text.
4. **Check strength determines the output label.** A passed deterministic check can endorse; a passed model check is weaker. Declare the check kind in the type.
5. **Idempotency:** mark calls idempotent or not. Non-idempotent calls (send, pay, external write) must not retry, or must use a dry-run-then-commit check. Retrying a deterministic call is only useful if prep changes the input.
6. **Typed escape:** a declared exit edge returning a structured failure (last attempt, reasons, exit cause: budget exhausted vs judged unrecoverable). No silent failure.
7. **Declared loop state:** what carries over between iterations, with labels. Exploration ("read until there's enough context") is expressible, but "enough?" is usually a model judgement, so it is a weak check, and the spec shows that.
8. **"Insufficient context" is a first-class failure reason**, letting the loop go back to prep with a request for specific extra material. Narrow context can then widen on demand through a governed channel.

## 7. Application: keeping a repo consistent with current intention

In an open loop, the **transcript is the record of intention**: X, then X′, then a partial retraction all stay in context and compete. Drift means acting on a superseded intention. Consistency ("update tests, docs and callers") is an obligation, so best effort.

A constrained harness can:
- **Own an explicit current-intent artefact** (spec or decisions record), updated through its own primitive when the user changes their mind. Superseded versions go to history and are not in working context.
- Give each edit primitive **the current intent plus the relevant repo slice**, not the transcript.
- Make consistency **structural**: after each edit, a check tests the diff against current intent and consistency rules.

**The trade-off:** narrow context reduces errors from noise but increases errors from **omission**. The preparer must judge relevance, which is the hard part.

**Redo after the event is acceptable for small tasks** (the economics of optimistic concurrency), provided that:
1. **Detection works.** The danger is an omission failure that *passes* the check, so put design effort into checking (against the intent artefact) more than into preparation.
2. **Effects are reversible.** Each primitive's effect is a commit on an unmerged working branch, so rollback is revert-and-rerun. This breaks with external non-idempotent effects.
3. **The redo differs.** The failure must feed back what was missing (from the checker, a later task, or the user). Otherwise a deterministic preparer reproduces the same poor context.
4. **Errors are contained.** Accepted poor results become context for later tasks, so per-task consistency checks limit propagation.

Resulting design: **cheap, fairly narrow preparer; strong checks; version control as rollback.**

## 8. Why constrained harnesses haven't dominated (so far)

Constrained designs exist (Agentless, AlphaCodium "flow engineering", DSPy, CaMeL) and once beat agent loops on benchmarks. Why the open loop won in general-purpose coding tools:

1. **Model–harness co-evolution:** models are RL-trained in open-loop harnesses, so they are in distribution there. Every model generation improves the loop for free. This compounds.
2. **Data-dependent exploration:** what to read next depends on what was just read. A fixed graph must anticipate that search or contain it in hand-written code.
3. **No cheap checks:** many steps ("right file?", "right abstraction?") have no cheap oracle. A constrained harness is only as governable as its checks.
4. **Attended use:** a human watching *is* the governance, so the cost of an ungoverned loop was low. Structure becomes necessary when unattended (hence Stripe).
5. **Generality:** constrained harnesses are designed per task class, while products need one harness for everything.

**Where the constrained design wins:** repetitive task classes, cheap per-step checks, unattended operation, adversarial inputs, and any setting needing the shape of every run known in advance for audit. These are the conditions of regulated, high-assurance environments.

## 9. Relevance to sensitive-data organisations

Open loops challenge the *current assurance process*, which needs enumerable behaviour, a data-flow map, and testing that bounds behaviour rather than sampling it. The problem is specifically **open loop + the trifecta**:
- An open-loop agent *without* the trifecta (sandboxed, read-only, no egress, trusted inputs) is assessable with existing controls.
- Useful mental model: **an insider working at machine speed who can be talked round by any document they read.**
- Keep supplier, hosting and provenance risk separate from the loop question.
- Constraint does **not** fix argument-level injection: control flow is locked, but injected content can still shape the arguments to permitted actions ("locks the verb, not the object").

Deployment pattern: no component holds all three trifecta legs; sensitive-data nodes get constrained control flow and no egress; untrusted-content nodes get no sensitive data, or only by reference; every outbound or irreversible action passes through a deterministic node; enforcement is effect-level.

**Core argument: governable means assessable.** A spec gives a security team a graph, invariants, and where each invariant is enforced, which maps onto artefacts they already review. An open loop gives them a model card and a system prompt.

## 10. Strongest objections

| Critic | Objection | Response / status |
|---|---|---|
| Bitter-lesson / frontier labs | Hand-built structure gets outgrown; minimal context destroys long-horizon coherence. | True for *capability*. But constraints here encode **requirements** (what must never or always happen), not task knowledge, and requirements don't go obsolete. Keep *task strategy* inside agentic nodes and fixed structure for requirements. The relevant comparison is best performance *among assessable systems*. |
| Workflow-engine veterans | This is BPMN again, and the spec language will become a bad programming language. | Build on existing engines. Expressiveness creep is a real risk that only discipline prevents. |
| IFC researchers | Label creep, declassify everywhere, approval fatigue, guarantees as theatre; argument injection survives. | **The strongest objection.** Empirical; must measure. |
| Formal methods | You verify the graph, not the meaning; validators may be wrong. | True. The claim is narrower: structure is verified, and assessment effort concentrates on a small set of functions rather than unbounded trajectories. |
| Delivery / procurement | Who writes specs? Ungoverned tools win on convenience; a novel runtime has no accreditation precedent. | Organisational, which is why it tends to decide outcomes. |
| Product / UX | Users want conversational redirection; rigid tools get bypassed. | Open. |

The killers are probably **label creep with approval fatigue** and the **economics of authoring and adoption**. Both are testable early.

## 11. Evaluation plan

**Experiment A: intent drift.** Build tasks where intention changes partway (requirement reversed, scope narrowed, naming convention switched). Run them in plain Claude Code and in the constrained harness. Measure:
- **Drift**: edits consistent with a superseded intention
- **Residual inconsistency**: tests, docs or callers not updated
- **Omission failures**: wrong results traced to missing context
- Redo rate and cost

The bet holds if the harness wins on the first two without losing badly on omission.

**Experiment B: label viability.** Take one real task class, label it honestly, and count declassifications, approvals and failed runs per task. If the counts are high, the architecture is not viable for that task class regardless of elegance.

## 12. Open questions

- Is there an expressive enough but statically analysable spec language? Where exactly is the line?
- How should a single agentic node's capability be capped to prevent the "escape-hatch node" that turns back into an open loop?
- Can models be fine-tuned to work *inside* this harness (state-dependent typed action menus, code-owned termination) to close the capability gap?
- How should weak (model-as-judge) endorsement be treated by downstream policy?
- Can the constraint graph be *learned* or *verified* rather than hand-written per task class?
- How do you make prohibitions effective against argument-level injection, beyond control-flow integrity?

## References

- Sutton, R. (2019). *The Bitter Lesson*.
- Schneider, F. B. (2000). *Enforceable Security Policies*. ACM TISSEC.
- Denning, D. E. (1976). *A Lattice Model of Secure Information Flow*.
- Myers, A. C. & Liskov, B. (1997/2000). Decentralized label model; Jif.
- Xia, C. S. et al. (2024). *Agentless: Demystifying LLM-based Software Engineering Agents*. arXiv:2407.01489.
- Debenedetti, E. et al. (2025). *Defeating Prompt Injections by Design* (CaMeL). Google DeepMind.
- Beurer-Kellner, L. et al. (2025). *Design Patterns for Securing LLM Agents against Prompt Injections*. arXiv:2506.08837.
- Willison, S. (2025). "The lethal trifecta" for AI agents.
- Liu, N. F. et al. (2023). *Lost in the Middle: How Language Models Use Long Contexts*.
- Stripe Engineering (2026). *Minions: Stripe's one-shot, end-to-end coding agents* (Parts 1–2).
- Anthropic (2024). *Building Effective Agents* (workflows vs agents).
