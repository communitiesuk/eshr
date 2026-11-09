---
title: Constrained agent harnesses — design notes
status: in-progress
date: 2026-11-09
---

# Constrained Agent Harnesses: Design Notes

*Status: exploratory design thinking, not a specification. Captured from a design discussion, November 2026.*

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

**There are no agentic (pre-built open-loop) nodes.** An earlier draft
allowed nodes that call an open-loop agent internally. They are ruled
out. This does **not** rule out open loops: one is trivially built as
a `loop` around an LLM node that suggests tools, with a `branch` to
the tool nodes and back. What the ban removes is the **black box**: a
pre-built open-loop harness whose tool calls, termination and context
happen out of sight and would need complex special handling. An open
loop built from LLM and tool nodes is in the graph, so it is typed,
bounded by a maximum number of tries, recorded at every transition,
and visible to the checker, which reports it as loose (§6.9).

Guarantees hold **at node boundaries**. Inside an LLM node there is a
single model call with no tool access; every tool use is a transition
in the graph. The design skill is cutting the graph so everything
that must be guaranteed sits on a boundary or in a deterministic node.

Both extremes exist: a pure workflow (Agentless is close to this) is
all deterministic or single-call nodes; Claude Code out of the box is
a single open loop that owns everything, including termination. eshr
can express the second only as an explicit loop in the graph, never
as a black box.

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

**Handles: keys held by nodes, values held by the runtime.** A node
that produces data generates its entries, keys and values, like a
dictionary. The runtime holds the dictionary, and the requirement is
that it reaches its consumer without any other node seeing it. So the
**runtime does the routing**, not the nodes: if a node held the
dictionary and passed it along, every node in between would see the
values.
- **Keys** flow along ordinary edges to any node that needs to refer
  to the data. They carry no content, so they do not taint.
- **Values** go only to nodes with a declared right to *dereference*
  them, granted in the spec like a capability. The checker verifies
  that every dereferencing node is cleared for the value's label; at
  run time the runtime refuses any lookup the spec did not declare.
- Keys are **opaque** (holding one reveals nothing) and **unforgeable**
  (the runtime issues them, so a model cannot invent or alter one).
- *Which* key a node chooses can still carry information: a node that
  picks keys after reading untrusted data can be steered in its
  choice.
- Handles make two patterns possible: **prose with handles, then
  deterministic rendering** (a model writes about data without seeing
  it, and code inserts the values), and **coverage checks** (§6.10),
  since coverage can be checked against keys but not against free
  prose. Handles therefore need to be a first-class type in the spec
  language.

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
- **Integrity matters for content, not only transitions.** Untrusted
  data that never drives a transition can still shape what a person
  reads, for example by suppressing findings in a report. Outputs
  meant for people should show, per item, whether code checked it or
  a model asserted it, and untrusted text rendered to a person needs
  safe display.
- **What matters at a sink is its clearance.** Sensitive content
  costs nothing when it goes to a sink cleared for it. Labels become
  expensive where model-written prose about sensitive content must
  reach a sink with a lower clearance on every run, because only a
  person can release it (probe B1, note 0009).
- **Keep the lattice small:** a handful of confidentiality levels and
  4–5 integrity classes, plus personal-data flags.

**Static policies, checked in CI on every spec change, for example:**
- No node holds all three legs of the trifecta.
- Every path to an outbound or irreversible action passes through
  approval or allow-list.
- Untrusted-labelled data never reaches a node that chooses
  transitions.
- All loops are bounded, so every run terminates.
- Declassification from level X requires a human approval node, or a
  deterministic `declassify` with a declared release rule (§6.2).

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
need an open loop is built from chains and loops of LLM and
deterministic atoms. That can recreate an open loop, but an explicit
one: in the graph, bounded, recorded and assessed, rather than a
black-box harness needing special handling (§3, §6.9).

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
- **A deterministic `declassify` declares its release rule**, for
  example "counts per enum value, no free text" or "enums and cell
  references, no values", so the checker can verify that its output
  schema releases only what the rule allows. **Open:** how release
  rules are expressed, and whether automated declassification by
  aggregation is acceptable or every declassification from a
  sensitive level needs a person. Probe B1 found this question
  load-bearing in both of its first two tasks (note 0009).

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
- **Endorsement strength follows what vouches for the content, not
  who runs the check.** A deterministic check that code established
  a fact is a full endorsement. A deterministic check of only the
  *form* of a model's judgement (valid enum, handles resolve) is weak,
  because the judgement's truth still rests on the model.
- **What weak endorsement may drive is a policy question.** A
  plausible default: a weakly endorsed value may choose low-stakes
  routes ("revise again", "move on to human review") but may not
  authorise egress, an irreversible effect, or skipping a human
  approval. **Open:** whether this default is right.

### 6.5 Combinators

This is a minimal set; other requirements may be identified during
development.

| Combinator | Meaning |
|---|---|
| `seq` | chain, when output and input signatures match (including labels and effects) |
| `branch` | dispatch on variants of a typed sum, including `Escape` and error variants |
| `loop` | bounded iteration with a declared state type and a maximum number of tries |
| `guard` | the specialised loop enclosing an LLM call (§6.4) |
| `map` / `par` | parallel execution, with recombination by a declared policy (below) |

**Recombination.** Because the runtime holds values and nodes hold
keys (§5), the runtime can issue a key when a branch *starts*, before
its value exists, as a promise. The key later resolves to a value or
to a failure variant. Recombination is then a declared rule about
when the consumer runs, relative to keys resolving:

| Policy | The consumer runs… |
|---|---|
| **wait for all** | when every key has resolved |
| **stream** | once per key as it resolves, or as an incremental fold over arrivals |
| **first / k of n** | when enough keys have resolved; the rest are cancelled or ignored |
| **deadline** | at a time limit, with unresolved keys becoming a `Timeout` failure variant |

A recombining combinator therefore declares:
- a **completion condition**: all, first, k of n, or a deadline;
- a **delivery mode**: batch or stream;
- a **failure policy**: fail-closed by default (one failure fails the
  lot, §6.8), or an explicit opt-in to a collection of results and
  failures.

Consequences:
- **Timeouts are failures** (§6.8): a branch that does not finish
  resolves to a runtime-defined `Timeout` variant, routable like any
  other. A deadline needs a declared clock as its event source.
- **Streaming makes labels accumulate.** A streaming consumer keeps
  state across arrivals, and its label is the join of everything that
  has arrived so far, rising over time. Streaming consumers need
  declared state with labels.
- **Arrival order affects replay.** Wait for all, ordered by input
  position, is deterministic. Streaming, first-of, k of n and
  deadlines can depend on which branch finished first. Either the run
  record captures arrival order and timeout events and replay feeds
  them back in the same order, or streaming consumers must be
  order-insensitive. Recording fits "the record is the data".
- **Coverage becomes completeness of accounting** (§6.10): when a
  branch can fail or time out, an obligation can require every key to
  appear in the output either as a result or as a declared failure,
  so nothing is silently missing.
- **Timing-dependent policies loosen a harness** (§6.9). Wait for all
  with fail-closed failure is the most constrained form.

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
- **Waits are bounded or declared.** Every wait on an external event
  (a person, CI, an API) declares either a deadline or an explicit
  block until the event arrives. A recorded block is not a hung
  process, so the second is acceptable; the checker refuses an
  undeclared indefinite wait.
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

**Partial failure in `map`/`par`** follows the recombining
combinator's declared failure policy: fail-closed by default, with an
explicit opt-in to accept a collection of results and failures
(§6.5).

### 6.9 Constrainedness assessment

The checker should report **how constrained a harness is**: how much
of what happens is fixed by the spec, and how much is left to
run-time content (model output, external systems). A first cut at
the dimensions:

| Dimension | What loosens it |
|---|---|
| **Control** | wide model-chosen branches (many variants from LLM output); catch-all routing arms; high maximum tries; timing-dependent recombination (streaming, first-of, k of n, deadlines) |
| **Data** | free-text fields feeding effects or transitions, rather than enums or opaque handles; label relaxations; weak (model-as-judge) endorsements |
| **Effects** | broad capabilities; non-idempotent effects; number of egress points |
| **Failure** | catch-alls into active continuations; atoms exposed to undeclared failure; author-declared variants left on the default route where the right response is likely context-dependent |

- **A profile, not a score.** A single number hides trade-offs and
  invites gaming. Report it per node, list the hot spots, and show it
  as a **diff between spec versions**, so a reviewer sees what a
  change widened.
- **It makes §2's continuum measurable.** An open loop can be built
  explicitly from LLM and tool nodes (§3), so open-loop and
  constrained-by-construction agents sit on one continuum within the
  same framework. This profile is the axis, and "how does
  performance change as constrainedness changes?" becomes an
  experiment the framework can run.
- **Obligations count too.** The profile should list which declared
  obligations are enforced by a deterministic coverage check (§6.10)
  and which rest only on weak, model-judged checks.
- **Open:** whether failure handling belongs in this one assessment,
  as the table assumes, or needs an assessment of its own. The
  current view is one assessment, because catch-alls loosen a
  harness in the same way wide branches and loops do.
- Prior art, from memory and unverified: cyclomatic complexity
  (counting paths); attack-surface metrics (Manadhata and Wing);
  quantitative information flow (for example Smith's min-entropy
  leakage), which measures how much a channel lets through rather
  than asking yes or no.

### 6.10 Enumerable obligations

Owning the control flow guarantees that a step **runs**. It does not
guarantee that the step's output **fulfils** an obligation: an LLM
step can run and still leave things out. For obligations whose
subject code can list, three things together close that gap:

1. **A deterministic step produces the facts the obligation is
   about**, so the set that must be covered is known exactly.
2. **Those facts carry handles and are labelled observed** (§5), so a
   model can neither invent members of the set nor drop them from it.
3. **A deterministic coverage check runs inside the guard** (§6.4):
   every key in the set must appear in the output, or, where items can
   fail, appear as a declared failure (completeness of accounting,
   §6.5). A miss loops back with a structured reason; running out of
   tries gives "not possible".

Either the output fulfils the obligation or the run says it could
not. It can never silently omit an item. Examples:
- every mechanical QA finding appears in the report (probe B1, task
  2, note 0009);
- every changed public function has a test (the diff lists the
  functions);
- every QA process in the user's list is addressed in a draft, if
  each has a handle.

Consequences:
- **Obligations can be declared in the spec**, for example "L2's
  output covers every key from N1", and the checker can confirm that
  each declared obligation has a deterministic coverage check. That
  makes some obligations assessable, not only prohibitions, and bears
  directly on §1, problem 1.
- **Limits.** It guarantees coverage, not quality: the check cannot
  tell whether an item is treated well. It works only where code can
  list the obligation's subject; "do a good review" stays weak.
- **Cost.** If a model often fails the coverage check, runs end in
  "not possible". B2 should measure how often.

## 7. Evaluation plan

### 7.1 Purpose: stopping tests, framework first

The first job of evaluation is to find **reasons to stop**, cheaply,
before most of the building. It evaluates the **framework first**: if
eshr is a good instrument for running experiments on constrainable
harnesses, it can then be used to run them.

The claims the note eventually needs to test:

| Claim | Source |
|---|---|
| **H1** A harness that owns the control flow is more assessable | §1, §4 |
| **H2** It may perform better, because each call gets context assembled for it | §1 |
| **H3** A CCA can perform comparably to an OLA | §2, question 1 |
| **H4** OLA and CCA sit on a continuum, and performance varies measurably with constrainedness | §2, question 2; §6.9 |

**H2 is deferred.** An eshr harness assembles context well only if
someone has built a good context assembler to fill the `prep` slot.
Until then, runs measure the *floor* of performance, not its
potential.

**Method.** Most blockers can be probed without building eshr at all,
by paper exercises or a hand-wired prototype (plain code, no spec
language, runtime or checker). If the premise fails there, the
framework would not have rescued it. Each **stopping criterion is
written down before the test is run**, so a result cannot be
explained away afterwards.

### 7.2 Hard blockers

**B1. Are labels workable?** A paper exercise, no code. Take two or
three real task classes, draw their graphs, label them honestly, and
count per task: declassifications, endorsements, weak endorsements,
human approvals, and nodes whose label ends up at the join of
everything.
- *Stop if* most LLM outputs end up maximally tainted even with
  field-level labels and opaque handles, or the human approvals per
  task make it unusable.
- Also walk some prompt-injection cases through the graphs on paper.
  Argument-level injection ("locks the verb, not the object") is the
  other likely assurance blocker.

**B2. Do models collapse under CCA conditions?** A hand-wired
prototype. Models are trained in open loops, and eshr changes several
things about how they are used, each of which could hurt performance
on its own. Isolate them where possible:
- tool *suggestion* through an output schema (a sum type), against
  native tool calling;
- no transcript: a single call over assembled context, with a
  deliberately naive `prep`;
- narrow retry feedback: an enum `Retry<Reason>`, against raw text.

Run a small task set as a hand-wired graph and as the same model in a
native tool loop.
- *Stop if* success drops sharply on tasks with cheap checks, which
  is where constrained designs should do well.

**B3. How far up the ladder can useful work go?** Because explicit
loops are allowed (§3), every task can be expressed at the open-loop
end, so decomposition is never strictly impossible. The risk is that
**every useful task only works near the bottom of the ladder**, in
which case eshr adds a framework without adding constraint. For B2's
tasks, record how far each can be narrowed before performance
collapses.
- *Stop if* realistic tasks all need near-open loops.

**B4. Does something already do this, and is it available?** A short
survey, not an experiment: CaMeL implementations, DSPy, BAML,
LangGraph, Temporal-based agent frameworks and similar.
- **Available** means usable without a procurement process: an open
  or freely usable licence, runnable in our own environment. A tool
  that needs government procurement to access counts for much less.
- *Stop or change course if* an available tool gives most of the
  value. That might mean building on it rather than stopping.

**Open:** which task classes to use for B1–B3. The choice matters
more than anything else here: they should span the cases where the
note predicts constrained harnesses win (repetitive work, cheap
per-step checks, adversarial inputs) and where they should struggle
(data-dependent exploration). myelin's drafter → reviewer → reviser
loop is a candidate, with a corpus of real runs to compare against.

### 7.3 Cost of building something worth using

**Worth using** means the smallest instrument that can run the ladder
experiment (§7.4) on one real task class.

| Component | Likely category |
|---|---|
| Running model calls | off the shelf |
| Durable execution and state | off the shelf (e.g. Temporal), or thin (plain code first) |
| Spec format | thin (a schema-checked data format first) |
| Run record and replay | thin to moderate |
| Type, label and effect checker | **novel**, though existing information-flow and effect type systems may cover much of it |
| Constrainedness profile | **novel**, but small once the checker exists |
| Built-in atoms (`guard`, `egress`, `endorse`, …) | moderate |

Durations are not estimated here. The estimating probe is the first
build stage: define, check, run and record an echo chain, and time
it. Then extrapolate to the ladder instrument from known units of
effort.

### 7.4 Later, if nothing stops it

- **The ladder experiment (H1, H3, H4).** For one task class, build a
  ladder of harnesses inside eshr, from an explicit open loop (the
  LLM may suggest any tool, high maximum tries) through
  progressively narrower graphs to a tightly constrained one. Same
  model, tools, tasks and runtime on every rung; only constrainedness
  varies, measured by the §6.9 profile. This avoids the confounds of
  comparing against an external harness. Comparison with an
  external agent such as Claude Code comes last, as a sanity check.
- **Measures.** Performance from the run record (task success, model
  calls, tries used, escapes, human blocks). Assessability at three
  levels: which policies the checker can prove on each rung; attack
  success on a prompt-injection suite (AgentDojo, used by CaMeL,
  scores both security and utility; from memory, to verify); and,
  most convincingly, human assessors given a spec and checker report
  against an open-loop configuration.
- **Replay as everyday evaluation.** Re-running recorded inputs
  through a revised harness and comparing check results judges each
  revision without external comparison.
- **H2** once a context assembler worth testing exists for `prep`.
