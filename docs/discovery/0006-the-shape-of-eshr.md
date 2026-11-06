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

5. **A library of chains:** preparers, checkers and the calls between them, grown from the bottom up.

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
- **The case for runtime matching** is mainly extension without editing. Adding a handler for a new kind of document should not mean editing every chain that might produce one. That case was found persuasive enough to keep open. Other reasons heard: human resolvers, running work when its inputs are ready, routing requests for more context, and swapping in revised primitives.
- **Shape alone cannot select a link.** Two primitives can have the same input and output shapes and do different things, and forbidding that would be needlessly constraining. So shape is the compatibility check, not what chooses the link. Selection is by name: a named link in a declared chain, or a named type (a draft and an approved draft are different types even with identical fields). This answers the structural-or-named question in favour of named types, and means conditional chains match on named types, not bare shape.
- **Middle grounds noted:** a registry that is itself part of the spec, so the checker can still list every match and a new registration shows as a diff; and higher-order chains that take a primitive as a parameter, as `map` takes a function.

**Scheduling: possibly all state and events.**

- **The intended behaviour:** the system keeps working until there are no tasks left for it (review, response, refactoring, drafting and so on), then waits until humans make more work available. The conditions for this should be configurable for each harness built with the runtime.
- **Ordering and waiting may collapse to state.** "B after A" is B needing A's output. Waiting for an external condition (a CI result, an approval, a date) is a typed value that arrives in state as an event. This collapses only if all ordering is expressed as data dependency and every external condition enters state as a typed value.
- **Where it may not collapse:** limits (budget, rate, concurrency), timeouts (the absence of an event, unless a clock is an event source), and supersession (when intent changes, pending work built on the old intent should be cancelled, 0002 §7).
- **Which human to involve is a decision, not wiring.** Choosing whom to tag is a final-stage primitive (a model or a rota lookup) whose output names the person. What is genuinely a runtime fact is whether and when they respond, and that is an event entering state, like any external condition. Humans and external systems are both sources of events.
- **Implication for question 2:** the runtime may provide the mechanism (state, events, running until there is nothing left to do) while each harness's spec supplies the scheduling policy.

### Sequencing

Working from first principles means starting with very basic primitives. So:

1. The primitive, a minimal runtime and the record.
2. Simple chains, evaluated on their own merits by replaying their records.
3. A growing library of chains, each designed, implemented, tested and revised.
4. A first real graph. Notes 0003 and 0004 suggest myelin's drafter → reviewer → reviser chain, but it is a long way off.
5. Comparison with existing agents, last.

## Open questions

To settle in this order:

1. **How do chains and branching relate?** In progress: see "Chains and branching" above. Still open within it:
   - Wiring is declared for now. Is extension without editing met by named-type dispatch over a registry in the spec, by higher-order chains, or by both?
   - What happens when no link matches an output, or more than one does?
   - How do parallel results recombine, and what does recombining receive when some elements came back "not possible"?
   - Does scheduling collapse entirely to state and events? If not, where do limits, timeouts and supersession live?
2. **What does "extensible" mean?** Is it 0002's slots (new behaviour by filling a slot, a new kind of node only by changing the runtime), or something more?
3. **How far does the first stage go?** What exactly sits in step 1 of the sequencing, and what counts as done?

Also open, not yet ordered:

- Is the governing artefact a roadmap issue or a first ADR that later ADRs implement?

## Next steps

- Work through the three open questions in order, extending this note as each is settled or narrowed.
- Then decide the form of the governing artefact, and draft it from this note.
