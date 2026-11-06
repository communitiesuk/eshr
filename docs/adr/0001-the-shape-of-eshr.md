---
title: What is the shape of eshr?
date: 2026-11-06
---

# What is the shape of eshr?

> **Directive for the implementer**: when implementing this ADR, invoke the `plans` skill to produce the corresponding plan artifact. Do not begin implementation without a plan.

## Context

eshr is a runtime for building harnesses: the code around a model. It can build an open loop, where the model decides, as easily as anything else. What it adds is the ability to build scoped harnesses, where the harness decides (README, "Why this exists"). eshr takes no position beyond hypotheses to be tested.

eshr grows out of myelin. The first full, real-world harness built with it will be a replication of myelin.

eshr aims to enable many people working asynchronously, without ruling out one person taking turns with one agent, as in myelin.

This ADR records, in outline, what eshr is made of and how the parts fit together. Later ADRs derive from it.

## Decision

### The primitive

- **The primitive is prepare → call → check.** The prepare step builds the input, the call does the work, and the check judges the result.
- **Every primitive is a chain.** A single primitive is a chain with one link.
- **Prepare and check are slots, filled by chains** built from the same primitive. The nesting ends at the base primitive, whose slots are filled by the base preparer and the base checker: built-in calls the runtime supplies. Nests go as deep as needed but never recurse without end.
- **The base checker can only be used with the base call.** As an opening position, every other checker is a primitive.
- **Context assemblers and check-step chains are built in eshr**, as families of chains; only the base preparer and checker come from the runtime. A context assembler is one kind of preparer; others assemble parameters for deterministic calls.
- **The check decides whether to stop or loop.** It either outputs, or goes round again with something that helps the preparer do better. A retry limit caps the looping; exceeding it means "not possible".
- **The output is the call's result, or "not possible".**
- **Each primitive has something like a system prompt** that steers its preparer.

### What eshr is made of

- **The primitive and its composition** into chains.
- **The runtime**, which runs chains and holds the control flow.
- **The policy checker**, which checks a harness spec before anything runs.
- **The run record.** It is not only an audit trail: it is the data that enables iteration.

### Chains

- **Declared types are the contract between links.** A link's declared output must be compatible with the next link's declared input requirements. Types are named: two primitives may share a shape and do different things, so compatibility between links is judged on named types, not bare shape.
- **There are three kinds of chain:** sequential (one link at a time, in order), parallel (each element of one link's output goes to a separate primitive) and conditional (the next link is the one whose declared input accepts the output's type). Parallel results can be combined by feeding them to a chain prepared to receive them.
- **Wiring is declared.** A chain lists its own links, as a function definition does.
- **"Not possible" is passed on along a chain, or up to the parent** where primitives are nested.
- **Any other declared output type that no next link's declared input accepts, or that more than one accepts, stops the harness compiling.** This is held provisionally.

### Scheduling, events and humans

- **Scheduling policy belongs to each harness.** A harness works until no tasks are left, then waits for people to make more work. Those conditions vary by harness, and may simply be part of its definition in the spec, not separate configuration.
- **Choosing which person to involve is a step in the harness**, so it need not be defined in the runtime, and who is chosen cannot be known at compile time.
- **Limits, a primitive's retry limit among them, and timeouts are events**, to be handled gracefully like any other.
- **Supersession is left to the harness**: the myelin replication.

### Extensibility and computation

- **Extensible means named composition.** A person can link existing chains into a new chain, name it, and use it in further chains or pass it in to fill a slot.
- **Computation happens only in calls.** This is held provisionally.
- **A complete harness is made of four elements**, each with its source:
  - wiring chains together: the runtime itself;
  - built-in calls, for common operations: eshr's developers;
  - chains composed from built-in calls, for most extensions: harness developers;
  - user-defined calls, for edge cases: harness developers.
- **Built-in calls, the base preparer and checker first among them, are defined in the runtime.** User-defined calls, a way to run outside code, will be needed.
- **Types follow the same pattern:** built-in, plus user-defined.

### The harness spec

- **The harness spec is its own artefact**, not code in the implementation language.
- **It starts as a schema-checked data format.** A syntax may follow later, as a front end producing the same structure.
- **Its data model is designed for all three kinds of chain.**

## Alternatives considered

- **Choosing the next link at run time, through a dispatcher or a registry outside the spec.** Not adopted: wiring is declared, and such matching would escape the reassessment a spec change triggers.
- **Choosing the next link by shape alone.** Rejected: same shape does not mean same behaviour.
- **Chains written in the implementation language.** Rejected: host code in the spec breaks "computation only in calls" and makes static checking unreliable.
- **Context assemblers and check-step chains as runtime components** (notes 0003, 0004). Replaced by chains built in eshr.
- **A substantial interface for "the human side".** Replaced by events, plus whatever shows the harness's state to people.
- **Note 0002's six node types.** Replaced by a single primitive.
- **A roadmap issue as the governing artefact.** Not chosen: it would sit outside git history and the trail that links artefacts.

## Consequences

- One primitive and declared wiring give the policy checker a closed graph to check before anything runs.
- A second hypothesis, to be tested rather than assumed: small composable computations beat monoliths.
- Left to later ADRs or still open:
  - a primitive's slots, and built-in calls beyond the base preparer and checker, including any other base calls or base checkers;
  - the model call layer (Agent SDK or Messages API) and the implementation language;
  - a durable-execution engine, such as Temporal;
  - tools for writing graphs;
  - how existing chains take up a new type without each being edited: a registry in the spec, higher-order chains, or both;
  - whether branching is wholly type-directed, and how exhaustive matching lives with adding new types;
  - how recombining works: gather and join, when it fires, partial failure and replay order;
  - the form of user-defined calls, and whether the policy checker and the run record handle kinds of call differently: for example, the checker listing every user-defined call, or the record keeping only the inputs of a deterministic call without effects, since replay recomputes it;
  - whether and how the runtime holds state and events, and how limits, timeouts and supersession behave in it;
  - which government assurance guidance to name, deferred to discovery.

## References

- README, "Why this exists": the hypothesis this ADR serves.
- myelin (`communitiesuk/myelin`): the first full harness to replicate.
