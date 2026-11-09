---
title: Constrained agent harnesses — design notes
status: in-progress
date: 2026-11-09
---

# Constrained Agent Harnesses: Design Notes

*Status: exploratory design thinking, not a specification. Captured from a design discussion, November 2026.*

*Version 2. Supersedes v1. Main change: the single recursive "prepare → call → check" primitive (v1 §6) is replaced by **typed atoms plus combinators**, with LLM calls enclosed by a `guard` combinator that the type system enforces. v1 (imported from myelin on 2026-11-06) stays in git history. Section 6 answers the open questions of discovery note 0007; §6.8 and §6.9 add failure handling and a constrainedness assessment, worked through on 2026-11-09.*

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
   only best effort. Governed context such as skills can ameliorate
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

Guardrails on open-loop agents (OLA) are clunky and frequently weak. The principal tools are:
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

One alternative would be to build this deterministic layer. Another would
be to abandon OLA entirely and design an agentic model
that is constrainable by construction (CCA).

Open questions are therefore:

1. Could a CCA model be designed? What would it look like? Could CCAs perform comparably to OLAs?
2. Does one in fact have to abandon OLA to build a CCA? or is there a continuum between them? (The constrainedness profile in §6.9 would make such a continuum measurable.)

## 3. Hybrid graphs

A **hybrid graph** is a harness whose top-level structure is a state machine written as code or a spec.

- **Deterministic nodes**: plain code (branch, lint, test, check diff scope, open PR). Their outputs are *facts*.
- **LLM nodes**: bounded loops around single LLM message calls with
  code-fixed boundaries: a set of tools the model may *suggest*,
  curated starting context, a maximum number of tries, and an output
  contract (schema).
- **Edges**: transitions owned by code, enabled by nodes' I/O signatures

**There are no agentic (open-loop) nodes.** An earlier draft allowed
nodes that call an open-loop agent internally. They are ruled out:
work that seems to need one is decomposed into chains or loops of LLM
and deterministic nodes (§6).

Guarantees hold **at node boundaries**. Because no node contains an
open loop, there is no open-loop regime anywhere in the graph: inside
an LLM node there is a single model call with no tool access. The
design skill is cutting the graph so everything that must be
guaranteed sits on a boundary or in a deterministic node.

Both extremes exist: a pure workflow (Agentless is close to this) is
all deterministic or single-call nodes; Claude Code out of the box is
a single open loop that owns everything, including termination. eshr
deliberately cannot express the second.

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
  LLM node suggesting a tool and the deterministic tool node being
  governed by their I/O signatures.
- **data labels** it may read, and labels on its outputs
- for LLM nodes: model, maximum number of tries, output schema

Per edge: a transition condition evaluated by code.

### 4.2 What the runtime enforces

- Each node runs with only its declared capabilities. Tools are
  separate nodes. Whether an LLM node can call them is enforced by
  the I/O signatures that govern node transitions.
- Output schema validation, maximum tries, ownership of transitions.
- A trace that provably follows a path through the declared graph.

### 4.3 Node types: a small, closed, sealed set

**Extension is by composition, not inheritance.** Each type has
*slots* (e.g. a function for a deterministic node; `prepare` and
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

- Specific types are beyond the scope of this note, apart from the
  built-in label and effect atoms listed in §6.2.

### 4.4 Nesting

A slot may be filled by another node or subgraph. Useful cases:
- An LLM node whose **suggested tools are first-class nodes** (an
  egress node with allow-list; a quarantined LLM node returning
  opaque handles). This is the CaMeL structure expressed as a spec.
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
schema), **not the implementation.** Model, prompt or maximum tries
can change inside a node without reassessment. Contract changes produce a
spec diff that triggers a policy re-check and review.

## 6. Core model: typed atoms plus combinators

**No open loops inside a guard.** An earlier draft allowed the central
call between `prepare` and `check` to be an open-loop agent with
read-only tools. That is ruled out. Even read-only tools give the model
direct access, bring untrusted or sensitive content into its context,
and can leak data (a read-only fetch can carry data in its URL). The
central call is always a single LLM message call. Work that seems to
need an open loop is decomposed into chains and loops of LLM and
deterministic atoms.

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
  in the output and handled by `branch`, not by a prepare/check loop
  (§6.8).
- **LLM call**: returns `Raw<T>`. It can only appear inside a `guard`
  (§6.4).
- **Built-in label/effect atoms**: `declassify`, `approval`, `egress`,
  and `endorse` for untrusted data entering by deterministic routes.
  These are the first-class label-relaxing and effect types that §4.3
  requires.

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

guard(prep, call, check, max_tries, state_type) : Input → Checked<T> | Escape<Failure>
```

- **`guard` is both derived and built in.** It can be built from
  `seq`, `branch` and `loop` with the `Raw`/`Checked` typing, and it
  also ships with the runtime as a built-in, so the common case is
  assured once.
- **Running out of tries means "not possible".** If `max_tries` is
  reached and the checker has still not accepted, the guard's output
  is `Escape<Failure>`.

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
| `loop` | bounded iteration with a declared state type and a maximum number of tries |
| `guard` | the specialised loop enclosing an LLM call (§6.4) |
| `map` / `par` | parallel execution and recombination |

### 6.6 Bounding the nesting

Nesting is bounded by **types, labels and maximum tries**, not by shape:
- **No general recursion** (no self-reference), so every composition
  is a **finite tree that can always be flattened**. The
  checker-of-a-checker regress stops because the tree is finite.
- **Run time is bounded by maximum tries, not budgets.** Every `loop`
  and `guard` declares a maximum number of tries, so every run
  terminates. eshr is a framework for experimenting with constrainable
  harnesses, not a deployable product, so there are no cost or token
  budgets: they would cripple the experiment without saying anything
  about constrainedness.
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
   reasons, and exit cause (maximum tries reached vs judged
   unrecoverable). It propagates through `branch` and the caller
   decides what happens. No silent failure.
5. **Nested escapes must be handled.** Anything that might contain an
   `Escape`, such as a checker containing a guard, has to handle it:
   by an explicit arm or by the default route (§6.8).

### 6.8 Failure handling

**Everything can fail.** Every atom's output implicitly includes
failure. There is no attempt to enumerate what *cannot* fail, the
same stance as treating unlabelled data as most restrictive. Handling
never means blind retry.

**Two tiers of failure mode,** split by who can anticipate them:
- **Known when the runtime is built:** maximum tries reached, schema
  invalid, a label refused at an edge, a capability denied, a
  timeout. These are the same in every harness, so the runtime ships
  a fixed default route for each.
- **Known only when a harness is built:** failures specific to a
  user-defined atom or an external system (for example `NotFound`,
  `RateLimited`, `RecordLocked`). The harness author declares them in
  the atom's signature, so they are part of the assessed contract.
- **Undeclared failure** is itself a runtime-defined variant: a
  user-defined atom failing in a way its author did not declare. The
  runtime catches and labels it, and the checker reports which atoms
  are exposed to it.

**Every failure mode is a distinct typed variant,** not one opaque
`Escape`, so it is always possible to specify a route for a
particular failure mode. The route can be any composition: a
fallback, an alternative atom, a human approval, or passing it up.

**Defaults are implicit in the syntax but explicit in the checked
graph.** Where no arm is written, the default route passes the
failure up to the enclosing composition and never retries. At the top
of a run it becomes "not possible": a recorded block that a person
resolves. The toolchain inserts defaults as visible arms in the
flattened graph before the checker runs, so the checker and the
record see every failure path. Implicit versus explicit is then a
matter of authoring convenience, not assurance, as with nesting
(§4.4).

**Failure payloads carry labels.** An error message from an external
system is untrusted input. Passing a failure up carries its label,
and only the variant tag may drive a transition, never the message
text.

**Catch-all arms reduce constrainedness.** An arm that routes *any*
failure to an active continuation merges situations the spec could
have told apart, like a wide branch or a wide loop (§6.9). Fail-closed
defaults do not: passing failure up to a recorded block is
deterministic and conservative.

**Open:** partial failure in `map`/`par`. One option is that one
failure fails the lot by default, with an explicit opt-in to accept a
collection of result-or-failure.

### 6.9 Constrainedness assessment

The checker should report **how constrained a harness is**: how much
of what happens is fixed by the spec, and how much is left to
run-time content (model output, external systems). A first cut at
the dimensions:

| Dimension | What loosens it |
|---|---|
| **Control** | wide model-chosen branches (many variants from LLM output); catch-all routing arms; high maximum tries |
| **Data** | free-text fields feeding effects or transitions, rather than enums or opaque handles; label relaxations; weak (model-as-judge) endorsements |
| **Effects** | broad capabilities; non-idempotent effects; number of egress points |
| **Failure** | catch-alls into active continuations; atoms exposed to undeclared failure; author-declared variants left on the default route where the right response is likely context-dependent |

- **A profile, not a score.** A single number hides trade-offs and
  invites gaming. Report it per node, list the hot spots, and show it
  as a **diff between spec versions**, so a reviewer sees what a
  change widened.
- **It makes §2's continuum measurable.** If open-loop and
  constrained-by-construction agents sit on a continuum, this profile
  is the axis, and "how does performance change as constrainedness
  changes?" becomes an experiment the framework can run.
- **Open:** whether failure handling belongs in this one assessment,
  as the table assumes, or needs an assessment of its own. The
  current view is one assessment, because catch-alls loosen a
  harness in the same way wide branches and loops do.
- Prior art, from memory and unverified: cyclomatic complexity
  (counting paths); attack-surface metrics (Manadhata and Wing);
  quantitative information flow (for example Smith's min-entropy
  leakage), which measures how much a channel lets through rather
  than asking yes or no.

## 7. Evaluation plan

Required
