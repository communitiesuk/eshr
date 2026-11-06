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

### Sequencing

Working from first principles means starting with very basic primitives. So:

1. The primitive, a minimal runtime and the record.
2. Simple chains, evaluated on their own merits by replaying their records.
3. A growing library of chains, each designed, implemented, tested and revised.
4. A first real graph. Notes 0003 and 0004 suggest myelin's drafter → reviewer → reviser chain, but it is a long way off.
5. Comparison with existing agents, last.

## Open questions

To settle in this order:

1. **How do chains and branching relate?** If everything is a chain, where does branching come from? Possibilities include escape edges, a link choosing from a fixed set of next links, or something else. The README talks about a "declared graph". The answer decides what the spec actually is.
2. **What does "extensible" mean?** Is it 0002's slots (new behaviour by filling a slot, a new kind of node only by changing the runtime), or something more?
3. **How far does the first stage go?** What exactly sits in step 1 of the sequencing, and what counts as done?

Also open, not yet ordered:

- Is the governing artefact a roadmap issue or a first ADR that later ADRs implement?

## Next steps

- Work through the three open questions in order, extending this note as each is settled or narrowed.
- Then decide the form of the governing artefact, and draft it from this note.
