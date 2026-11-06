---
title: The shape of eshr
status: in-progress
date: 2026-11-06
---

# The shape of eshr

## Problem

Before the first ADR, we need a shared view of what eshr is made of, what gets built in it, and in what order. The aim is a governing artefact: a roadmap issue, or a first ADR that later ADRs implement (which one is not decided). This note is the thinking that comes before it. It draws on notes 0001–0005 but supersedes them where they disagree, because thinking has moved on since they were written.

## What we've covered

### The primitive is the unit, and everything is built from it

The core primitive is prepare → call → check (0002 §6). Thinking since then:

- **Every primitive is a chain.** A single primitive is a chain with one link.
- **Prep and check are chains themselves**, built from the same primitive. Plain functions are the base case that stops the nesting.
- **Preparers come in kinds.** A context-assembling preparer builds input for a model call. Other preparers assemble parameters for a deterministic call.
- **The context assembler is not a runtime component.** It is a family of preparer chains, built in eshr. Notes 0003 and 0004 treat it as a separate part. That is superseded here, though it remains where the bet is riskiest (README, "What would prove it wrong").
- **The checker is the same.** Checks are chains, built in eshr.

### What eshr is made of

1. **The primitive and its composition:** the chain as the unit, with nesting in prep and check.
2. **The runtime:** runs chains, holds the control flow, and keeps state rather than a running process (0003, 2026-10-27).
3. **The static policy checker:** checks specs before anything runs, against rules such as bounded loops, no step holding all three legs of the trifecta, and approval before anything leaves the system (0002 §5). It works on fully flattened chains, so nesting adds nothing it must understand. With the spec, it is what an assessor actually uses. Agreed as a core part.
4. **The run record:** not only an audit trail. **The record is the data that enables iteration**: every revision to a chain is made from it.

### What gets built in eshr

5. **A library of chains:** preparers, checkers, and the primitives whose call steps they serve, grown from the bottom up.

### Consequences drawn so far

- **Early evaluation comes from the record.** Note 0004's decoding test (replay recorded inputs through a revised codebook) applies to any chain: replay its recorded inputs through a revised version and compare the check results. This judges what has been built on its own merits and needs no external comparison.
- **Multiplayer async, not single-player turn-taking.** One aim is to move away from one person and one agent taking turns, towards many people working asynchronously. Keeping state rather than a process is the way in: a run lives in stored state, a block is recorded with its reason, and an event restarts the run. Who resolves a block is a matter of who can see the state and act on it, not whose turn it is. The "human side" is therefore mostly the runtime's state and event model, plus whatever shows that state to people.
- **The model call layer is an implementation detail.** For single tool-less model calls, the Agent SDK (0005) may be the wrong base, because it is itself an open-loop harness. This belongs with other implementation choices such as language, in later ADRs.

### Chains and branching (open question 1, in progress)

**Inside a primitive.**

- **The check decides whether to stop or loop.** It either stops and outputs, or goes round again with something that helps the preparer do better. It works as a review loop.
- **The output is the result of the call, or "that wasn't possible".** Both are outputs. The second is 0002 §6's escape edge, expressed as a kind of output rather than a separate exit.
- **A primitive has something like a system prompt that steers its preparer.** It states what the primitive is for.

**Between primitives.**

- **Input and output shapes are the contract.** Each primitive declares the shape of input it expects and output it produces. p0's output must be compatible with p1's input. A lot of the architecture could hang on this.
- **There are three kinds of chain:**
  - *Sequential:* one link at a time, in order.
  - *Parallel:* one link outputs a list, and each element becomes the input to a separate primitive, processed in parallel. The opposite case, recombining results, is not yet thought through but will probably be needed.
  - *Conditional:* one link can produce a range of output types, and the next link is the one whose input shape matches. This could extend to parallel processing, for example a list whose elements have different types.

**Implications noticed so far (not decided):**

- **Branching is type-directed.** Choosing the next link works like pattern matching on the output's type. If "not possible" is an output type, escalation is not a special mechanism: it is a link whose input matches that type.
- **This fits 0003's claim that the DAG "falls out of the contracts".** If links are matched by shape, the graph can be worked out from declared types, and so can the parallelism.
- **Assurance needs the matching to be static.** The policy checker can enumerate behaviour only if it can compute every possible match before anything runs.

**Wiring: declared, with the case for runtime matching heard.**

- **Current view: a chain lists its own links.** In the language spec, chains are like function definitions. A sequential chain is composition, a parallel chain is `map`, and a conditional chain is a `match` on the output's type.
- **The case for runtime matching** is mainly extension without editing. Adding a primitive that accepts a new kind of document should not mean editing every chain that might produce one. That case was found persuasive enough to keep open. Other reasons heard: human resolvers, running work when its inputs are ready, routing requests for more context, and swapping in revised primitives.
- **Shape alone cannot select a link.** Two primitives can have the same input and output shapes and do different things, and forbidding that would be needlessly constraining. So shape is the compatibility check, not what chooses the link. Selection is by name: a named link in a declared chain, or a named type (a draft and an approved draft are different types even with identical fields). This answers the structural-or-named question in favour of named types, and means conditional chains match on named types, not bare shape.
- **Middle grounds noted:** a registry that is itself part of the spec, so the checker can still list every match and a new registration shows as a diff; and higher-order chains that take a primitive as a parameter, as `map` takes a function.

**Scheduling: possibly all state and events.**

- **The intended behaviour:** the system keeps working until there are no tasks left for it (review, response, refactoring, drafting and so on), then waits until humans make more work available. The conditions for this should be configurable for each harness built with the runtime.
- **Ordering and waiting may collapse to state.** "B after A" is B needing A's output. Waiting for an external condition (a CI result, an approval, a date) is a typed value that arrives in state as an event. This collapses only if all ordering is expressed as data dependency and every external condition enters state as a typed value.
- **Where it may not collapse:** limits (budget, rate, concurrency), timeouts (the absence of an event, unless a clock is an event source), and supersession (when intent changes, pending work built on the old intent should be cancelled, 0002 §7).
- **Which human to involve is a decision, not wiring.** Choosing whom to tag is a final-stage primitive (a model or a rota lookup) whose output names the person. What is genuinely a runtime fact is whether and when they respond, and that is an event entering state, like any external condition. Humans and external systems are both sources of events.
- **Limits and timeouts are external events too.** Budget exhausted, rate limited and timed out are events that may block, and must be handled gracefully, like any other outcome. One nuance: a limit such as budget has to be enforced *before* the spend (a safety property, 0002 §2). The event reports that the runtime refused, not that the limit was crossed. A timeout needs a declared clock as its event source.
- **Supersession is a harness concern, and myelin is the harness.** eshr grows out of myelin (`communitiesuk/myelin`), whose whole point is to manage real-world project events such as supersession. The runtime needs only enough mechanism for state changes to invalidate pending work: for example, readiness is re-evaluated over current state, and an in-flight output based on superseded input fails its check.
- **Implication for question 2:** the runtime may provide the mechanism (state, events, running until there is nothing left to do) while each harness's spec supplies the scheduling policy.

**Matching and recombining: first thoughts, with drawbacks.**

*No link matches, or more than one does: proposed as a compile error.*

- **No match is prevented at run time already**, because a call's output is checked against its declared type before anything uses it. An output that fits no declared type fails the check: it loops back or becomes "not possible".
- **So every output, including "not possible", must have a next link that accepts it.** This is like an exhaustive `match`. *Drawback:* writing an escalation path at every link is heavy. *Possible relief:* an unhandled "not possible" passes up to the enclosing chain, like Rust's `?`. A catch-all arm would weaken assurance, but the checker could list catch-all arms.
- **More than one match as an error rules out implicit fan-out**, where one output goes to two consumers (say a reviewer and a logger). Fan-out would need the explicit parallel form. That is probably a good thing.
- **Drawback: exhaustiveness pulls against extension.** Adding a new output type (the new-document case) breaks every exhaustive match on that output until each is updated. This is the "expression problem", and it bears on question 2.

*Recombining: proposed as passing several chains' outputs as elements of a collection to a chain that handles collections.*

"Collection" here is not a formal list: the elements need not be ordered or of one type. The points below were first made about a typed list. They still apply to a collection, except that a collection already allows mixed types.

- **A list fits a parallel map**, where every element has the same type. **It fits fan-in from different chains less well**: the list's element type becomes a union, and which result came from which branch is lost. A record with one named field per branch may suit that case. So there may be two kinds of recombining: *gather* (map results into a list) and *join* (different branches into a record).
- **When does recombining start?** When all results are in, the first, or a quorum? Waiting for all of them blocks for ever if one branch waits on a person who never responds, so it depends on timeouts as events.
- **Partial failure.** Elements may be "not possible". Either the recombining chain accepts a list of result-or-failure, or one failure fails the lot.
- **Order.** Parallel results arrive in any order. For replay to be reproducible, the list should follow input order, not arrival order.
- **Size.** A long list going into a model call needs its preparer to select and compress. That is the context assembler again. The output's confidentiality label is the join over every element (0002 §5).

### Extensibility (open question 2, settled in outline)

**What "extensible" means: named composition in the spec language.** A person can:

- define a new chain by linking existing chains;
- give it a name;
- use it to define further chains, or pass it in to fill a slot and so make a new chain link (higher-order composition).

This is the function-definition analogy again: chains are defined, named, used inside other chains and passed as arguments.

**Computation happens only in calls.** "Call" here means the middle step of prepare → call → check, not running a chain. The spec language wires calls together; it does not compute anything itself. This is current thinking, held with some uncertainty.

**A further hypothesis: small composable computations beat monoliths.** This sits alongside the README's hypothesis, and like it should be tested rather than assumed.

**Four tiers, by analogy with a programming language** that has built-in functions and operators, libraries written by users, and functions written in other languages (as R does with Rcpp):

| What | Where it lives |
|---|---|
| Wiring chains together | the runtime |
| Common, frequently used calls | built-in calls |
| Most extensions | chains composed from built-in calls |
| Edge cases | user-defined calls |

Consequences noticed so far (not decided):

- **User-defined calls are the sanctioned `exec`.** Some kind of `exec` will be needed. Running tests on generated code, which myelin needs, is already this case (0001's "action nodes that run model output are hot spots"). Following 0001 and 0002, a user-defined call should declare its input and output types and its capabilities, run sandboxed, and be visible to the checker and the record, like Rust's `unsafe`.
- **Assessment effort concentrates where it should.** Built-in calls are assured once, with the runtime. Composed chains add no new effects. User-defined calls are the only new code an assessor must read, and the checker can list every one. This is 0002 §10's claim that assessment concentrates on a small set of functions rather than unbounded trajectories.
- **Every computation is recorded**, however small, because it happens in a call. That makes the record fine-grained, and lets each small piece be replayed and revised on its own. The cost is volume. One option: calls that are deterministic and have no effects need only their inputs recorded, because replay can recompute their outputs.
- **Calls may fall into kinds** that the checker and the record treat differently: deterministic with no effects, deterministic with effects, and model calls.

**Types follow the same pattern:** built-in types, plus named types defined in the spec language.

**Left to later ADRs:** a primitive's slots and the set of built-in calls. Both are expected to change during development.

### The first stage (open question 3, in progress)

**Goal: define and run a very simple chain, even if all it does is echo its input.**

**Split into two stages, as separate concerns:**

- **Stage 1a: define, check and run.** Define the echo chain in the spec, have the policy checker pass it, run it, and write the record.
- **Stage 1b: revise systematically.** Replay a recorded run against a revised primitive and compare the results. This depends on 1a, but once 1a exists there must be a systematic way to revise, so it follows straight on.

Current view on what is in:

- **Model calls, from the start.** eshr is about building harnesses.
- **A spec language with its own syntax**, rather than chains built in the implementation language.
- **A policy checker.**
- **Plain synchronous runs.** State and events come later.
- **Chain kinds:** sequential only would be much quicker. Doing all three would probably give a neater, more consistent runtime. Not yet decided.

Points raised (not decided):

- **The spec should not be code in the implementation language.** An internal DSL (chains written in Python, say) would let arbitrary host code into the spec, which breaks "computation only in calls" and makes static checking unreliable. So the spec needs to be its own artefact.
- **A data format first, syntax later.** One way to get a real spec without designing a syntax while the semantics still move: write specs in a schema-checked data format (YAML, JSON or similar), which is in effect the parsed structure. The checker and runtime work on that structure. A proper syntax later becomes a front end that produces the same structure. *Drawback:* data formats are clumsy for function-like composition (named chains, chains passed into slots).
- **Conditional matching is needed even for a sequential echo chain.** Every primitive's output is either its result or "not possible", so even one link must branch on the output's type. That suggests sequential plus conditional in the first stage, with parallel (which brings recombining and scheduling, the least settled parts) deferred.
- **An echo chain is a good first test.** A model call asked to repeat its input, with a deterministic check that the output equals the input, exercises prep, call and check, the retry loop and the "not possible" exit, and gives a check whose result is unambiguous.

### Sequencing

Working from first principles means starting with very basic primitives. So:

1. The primitive, a minimal runtime and the record: (1a) define, check and run a simple chain; (1b) replay its record against a revised primitive.
2. Simple chains, evaluated on their own merits by replaying their records.
3. A growing library of chains, each designed, implemented, tested and revised.
4. The first full, real-world harness: a replication of myelin. Smaller pieces of it, such as myelin's drafter → reviewer → reviser chain (0003, 0004), may come earlier, but the whole is a long way off.
5. Comparison with existing agents, last.

## Open questions

To settle in this order:

1. **How do chains and branching relate?** In progress: see "Chains and branching" above. Still open within it:
   - Wiring is declared for now. Is extension without editing met by named-type dispatch over a registry in the spec, by higher-order chains, or by both?
   - No match or more than one match as a compile error: does an unhandled "not possible" pass up to the enclosing chain, and how does exhaustiveness live with adding new types?
   - Recombining: is a list enough, or is a record-shaped join needed too? When does recombining start, and how are partial failures handled?
2. **What does "extensible" mean?** Settled in outline: see "Extensibility" above. Named composition in the spec language; computation only in calls, in four tiers from runtime to user-defined calls; types follow the same pattern.
3. **How far does the first stage go?** In progress: see "The first stage" above. Split into 1a (define, check, run) and 1b (replay and revise). Still open: which chain kinds, and the spec format.

Also open, not yet ordered:

- Is the governing artefact a roadmap issue or a first ADR that later ADRs implement?

## Next steps

- Work through the three open questions in order, extending this note as each is settled or narrowed.
- Then decide the form of the governing artefact, and draft it from this note.
