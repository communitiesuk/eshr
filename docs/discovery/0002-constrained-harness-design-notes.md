---
title: Constrained agent harnesses — design notes
status: in-progress
date: 2026-11-09
---

# Constrained Agent Harnesses: Design Notes

*Status: exploratory design thinking, not a specification. Captured from a design discussion, November 2026.*

*Version 2. Supersedes v1. Main change: the single recursive "prepare → call → check" primitive (v1 §6) is replaced by **typed atoms plus combinators**, with LLM calls enclosed by a `guard` combinator that the type system enforces. The rejected v1 design and the reasons for rejecting it are recorded in Appendix A.*

## 1. Problem

Current coding-agent harnesses (Claude Code, Codex and similar) use an
**open loop**: the model decides which tool to call next and when to
stop. In functional terms, it constructs its own graph to complete
tasks. Constraints are added from outside, through permission modes,
sandboxes and hooks, but the model owns the control flow.

Two motivating problems:

1. **Behavioural guarantees.** It is hard to make an open-loop agent
   reliably keep a repository consistent with the user's *current*
   intention. Intentions change during a session, superseded
   instructions stay in the transcript and compete with current ones,
   and obligations such as "always update tests and docs to match" are
   only best effort. Governed context such as skills can ammeliorate
   this problem but not entirely solve it.
2. **Deployability in conservative, sensitive-data organisations**
   (for example government). Assurance processes assume behaviour and
   data flows can be enumerated in advance. Open-loop agents decide
   their flows at run time, so they cannot be assessed in those terms.

**Working hypothesis:** a harness that owns the control flow and
manages context, with the model used only where a transformer is
actually needed, can be *more assessable* and may be *better
performing*, because each model call can be given context assembled
specifically for that call, rather than doing inference from the
transcript history.

## 2. Key distinction: what guards can and cannot enforce

Guardrails on open-loop agents (OLA) are clunky and frequently weak. The principle tools are:
  - **Limit actions**, e.g. never push to main, either by allow/deny
    lists or by sandboxing. These can work but are easily routed
    around - a model that decides its task needs code on main can
    easily write a script to do it. Agents are notoriously good at
    escaping their sandboxes.
  - **Manage Context** e.g. with skills or AGENTS.md, to instruct
    agents to always or never do some action, or only in certain
    situations. This is inherently best-effort and even frontier
    models forget/ignore/skip these instructions sometimes.
  - **Make separate agent calls**, e.g. with sub-agents, for
    individual tasks, e.g. one sub agent suggests an action, another
    decides whether it is safe and acceptable, and only then does a
    third subagent execute the action. But these rely either on
    managed context (which is unreliable) or on an external,
    deterministic orchestrator layer.
	
The conclusion is therefore that governance may be possible for
open-loop agents over bounded tasks, but will require additional
determinism to enforce. 

One alternative would be build this deterministic layer. Another would
be to abandon OLA entirely and design an agentic model
that is constrainable by construction (CCA).

Open questions are therefore:

1. Could a CCA model be designed? What would it look like? Could CCAs perform comparably to OLAs?
2. Does one in fact have to abandon OLA to build a CCA? or is there a continuum between them?

## 3. Hybrid graphs

A **hybrid graph** is a harness whose top-level structure is a state machine written as code or a spec.

- **Deterministic nodes**: plain code (branch, lint, test, check diff scope, open PR). Their outputs are *facts*.
- **LLM or Agentic nodes**: 
  - **LLM nodes** are bounded loops around single LLM Message calls
    with code-fixed boundaries: a tool set, curated starting context,
    a budget, and an output contract (schema).
  - **Agentic nodes** have the same similar signature but internally
    call open loop agents instead of LLM Message loops. Less specific,
    less bounded, less observable, more flexible.
- **Edges**: transitions owned by code, enabled by nodes' I/O signatures

Guarantees hold **at node boundaries**. *Inside* an agentic node you
are back to the open-loop regime, with guards for prohibitions and
best effort for obligations. The design skill is cutting the graph so
everything that must be guaranteed sits on a boundary or in a
deterministic node.

Both extremes exist: a pure workflow (Agentless is close to this) is
all deterministic or single-call nodes; Claude Code out of the box is
a single agentic node that owns everything, including termination.

Production precedent: Stripe's "Minions" use **blueprints** that
interleave deterministic nodes (lint, CI, push) with agentic loops,
for unattended runs, with CI retries capped at 2.

## 4. Proposal: a spec-interpreting harness runtime

A **runtime that interprets a declarative spec for a hybrid graph.**

- The **spec is the assessment artefact.** Security teams review specs against policy.
- The **runtime is the reference monitor**, assured once.
- The novel parts are the **type and label system for nodes' I/O
  signatures**, and **the static policy checker**.

### 4.1 What the spec declares

Per node:
- **type** (see 4.3)
- **capabilities**: tools, credentials, network egress, filesystem
  scope. Note that in this context 'tools' does not mean 'the ability
  to use tools' it means 'the ability to suggest tool use'. Tools
  themselves are deterministic nodes, with the transition between an
  agentic node suggesting an tool and the deterministic tool node
  being governed by their I/O signatures.
- **data labels** it may read, and labels on its outputs
- for agentic/LLM nodes: model, budget, output schema

Per edge: a transition condition evaluated by code.

### 4.2 What the runtime enforces

- Each node runs with only its declared capabilities. Tools are
  separate nodes. Whether an LLM or agentic node can call them is
  enforced by the I/O signatures that govern node transitions
- Output schema validation, budgets, ownership of transitions.
- A trace that provably follows a path through the declared graph.

### 4.3 Node types: a small, closed, sealed set

**Extension is by composition, not inheritance.** Each type has
*slots* (e.g. a function for a deterministic node; `prepare`, and
`check` functions for LLM nodes). Slot fillers run **inside** the
node: the node acts as host and monitor, starting the filler with
declared capabilities, validating its output, applying the type's
label rule, and handing results to the transition logic. Fillers
cannot alter the type's semantics. Subclassing is ruled out because it
would allow overriding them.

**Being a first-class node type matters.** Relaxing a label is
*syntax*, not convention, so the checker can list every point where
trust is raised or sensitivity lowered, and enforce policy on
them. This is the same idea as Rust's `unsafe` and Jif's `declassify`
/ `endorse` keywords.

- New *behaviour* means writing a function for an existing slot: cheap, everyday, checked by policy.

- A new *kind* of node means changing the runtime: rare, and goes through the runtime's own assurance.

- Specific types  are beyond the scope of this note.

### 4.4 Nesting

A slot may be filled by another node or subgraph. Useful cases:
- An agentic node whose **tools are first-class nodes** (an egress
  node with allow-list; a quarantined agentic node returning opaque
  handles). This is the CaMeL structure expressed as a spec.
- A subgraph of deterministic checks used as a validator.

**Rule: the outer type bounds the inner.**
- Capabilities only shrink.
- Labels follow the pessimistic path.
- **Every nested structure must flatten.** Policies run on the flattened graph, so nesting is an authoring convenience with no new semantics.

## 5. Data labels (information flow control)

Every value crossing an edge carries a label **assigned by the
runtime**, never self-declared by a node. Anything unlabelled is
treated as the most restrictive case.

**Two independent axes:**
- **Confidentiality**: who may see the value. Map it to the existing
  classification scheme (for example OFFICIAL, OFFICIAL-SENSITIVE)
  plus flags such as personal data. Governs **exfiltration**.
- **Integrity / provenance**: user instruction, system-trusted,
  observed by a deterministic node, model-generated, untrusted
  external. Governs **injection**.

Combining inputs raises confidentiality and lowers integrity (the **join** rule).

**The "lethal trifecta"** (Willison: private data, untrusted content,
exfiltration channel) becomes a graph check: no node simultaneously
holds high-confidentiality inputs, low-integrity inputs and an
outbound capability.

**LLM nodes mix every label in their context.** Any output token may
depend on any input token, so the output takes the join of the whole
context. This causes **label creep**. Mitigations:
- **Context minimisation**: everything a node sees taints its output.
- **Opaque references** (CaMeL): pass handles, not content, so
  privileged nodes can route data without being contaminated.
- **Quarantined nodes** with no capabilities and constrained outputs
  for processing untrusted content.

**Other rules:**
- **Narrow channels:** a validator turning free text into an
  allow-listed enum or boolean leaves little room for an injection to
  pass through.
- **Label fields, not messages.** In `{decision: enum, rationale:
  text}`, `decision` can be endorsed while `rationale` stays tainted
  and can never drive a transition.
- **Observed vs asserted:** tag whether a value was observed (test
  result, database read) or asserted by a model. Unverifiable claims
  then cannot pass as facts.
- **Keep the lattice small:** a handful of confidentiality levels and
  4–5 integrity classes, plus personal-data flags.

**Static policies, checked in CI on every spec change, for example:**
- No node holds all three legs of the trifecta.
- Every path to an outbound or irreversible action passes through
  approval or allow-list.
- Untrusted-labelled data never reaches a node that chooses
  transitions.
- All loops are bounded, so every run terminates.
- Declassification from level X requires a human approval node.

**Assessment attaches to the node contract** (capabilities, labels,
schema), **not the implementation.** Model, prompt or budget can
change inside a node without reassessment. Contract changes produce a
spec diff that triggers a policy re-check and review.

## 6. Core model: typed atoms plus combinators

In the following passages 'Agentic' may be substituted for 'LLM' - the
only difference is that 'Agentic' means the central call between the
`prepare` and `check` slots is a OLA with read-only tool use that can
only output a schema, while 'LLM' indicates a single message call.

### 6.1 Principle

Composition is an **algebra**, not one recursive shape: a small set of
**typed atoms** combined by a small set of **combinators**. Atoms
chain, loop and branch according to the contracts of their I/O
signatures.

Only **LLM calls** need enclosing in prepare/check loops. The loop
exists to manage an *untrustworthy* call. A deterministic call meets
its output contract by construction, so a checker adds nothing.

### 6.2 Atoms

- **Deterministic call**: a typed function with declared
  capabilities. It is a primitive in its own right. Calls to external
  systems can *fail* (network, API errors). That is **failure
  handling, not validation**: it is expressed as a typed error variant
  in the output and handled by `branch`, not by a prepare/check loop.
- **LLM call**: returns `Raw<T>`. It can only appear inside a `guard`
  (§6.4).
- **Built-in label/effect atoms**: `declassify`, `approval`, `egress`,
  and `endorse` for untrusted data entering by deterministic routes
  (see §4.3).

### 6.3 Signatures carry schema, label and effects

A signature is **(schema, label, effects)**. "Chain if signatures
match" therefore checks three things at once:
- schema compatibility
- legal label flow (the join rule; no low-integrity data into
  transition-choosing positions; and so on)
- capabilities

Most policies from §5 (the trifecta, endorsement rules, egress
constraints) then become **type errors**, not a separate policy pass.

### 6.4 The `guard` combinator: enclosing LLM calls by type

The three roles have **different signatures**:

```
prep  : (Input, State, Feedback) → CallInput
call  : CallInput → Raw<T>                        -- LLM call
check : (CallInput, Raw<T>) → Accept<T> | Retry<Reason> | Escape<Failure>

guard(prep, call, check, budget, state_type) : Input → Checked<T> | Escape<Failure>
```

- `Raw<T>` may flow **only** into a checker. Only a checker's `Accept`
  produces `Checked<T>`, the only type other atoms accept. Unchecked
  LLM output cannot be used anywhere because it will not
  type-check. **Enclosure is enforced by typing, not by a special
  primitive shape.**
- `prep` and `check` are themselves compositions of atoms and
  combinators. They may contain further guards.
- **The checker's `Accept` is the endorsement point.** Whether it
  raises integrity depends on the declared check kind: deterministic
  means real endorsement; a checker containing an LLM guard
  (model-as-judge) gives a **weak endorsement** label downstream.

### 6.5 Combinators

This is a minimal set; other requirements may be identified during
development.

| Combinator | Meaning |
|---|---|
| `seq` | chain, when output and input signatures match (including labels and effects) |
| `branch` | dispatch on variants of a typed sum, including `Escape` and error variants |
| `loop` | bounded iteration with a declared state type |
| `guard` | the specialised loop enclosing an LLM call (§6.4) |
| `map` / `par` | parallel execution and recombination |

### 6.6 Bounding the nesting

Nesting is bounded by **types, labels and budgets**, not by shape:
- **No general recursion** (no self-reference), so every composition
  is a **finite tree that can always be flattened**. The
  checker-of-a-checker regress stops because the tree is finite.
- **Weak checks stay visible** through endorsement labels.

### 6.7 Other Rules

1. **Effects are confined to declared call sites.** Inside a guard,
   `prep` and `check` hold read-only capabilities. Every side effect
   is a declared atom with declared capabilities.
2. **The loop-back is a channel.** `Feedback` from check to prep can
   carry taint. Either propagate labels honestly, or **narrow the
   channel**: `Retry<Reason>` holds structured reasons (enum plus
   deterministic diagnostics), not raw model text.
3. **Idempotency:** mark effectful atoms idempotent or
   not. Non-idempotent atoms (send, pay, external write) must not sit
   inside a retry loop, or must use a dry-run-then-commit pattern.
4. **Typed escape:** `Escape<Failure>` returns the last attempt,
   reasons, and exit cause (budget exhausted vs judged
   unrecoverable). It propagates through `branch` and the caller
   decides what happens. No silent failure.

## 11. Evaluation plan

Required
