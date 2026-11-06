---
title: "The primitive: bounding the nesting, and what the checker is"
status: in-progress
date: 2026-11-06
---

# The primitive: bounding the nesting, and what the checker is

## Problem

ADR 0001 (PR #5, held) says the primitive is prepare → call → check, that prepare and check are slots filled by chains, and that the nesting ends at a base primitive whose slots hold the base preparer and base checker, built-in calls the runtime supplies. A retry limit caps the check loop; exceeding it means "not possible".

The human is not yet happy with this as a general concept: "I think we're on the right lines, but I also feel like I still haven't really reached a principle for bounding the nested chains, and that although the preparer and checker are both chain shaped slots, they are fundamentally different chains. In particular the checker carries a decision. It feels like a few things follow from that and I haven't really identified or understood them."

Two questions, then: what is the principle that bounds nested chains, and what follows from the checker carrying a decision?

## What we've covered

**How we got here.** The ADR's end to the nesting has moved several times during review: plain functions (note 0006), a single call, a prepare or check step that passes its input through, a prepare step only, then the base primitive. Each was a patch to a regress, not a principle. The PR #5 commit history records each step.

**The base primitive, as the human described it.** Assume inputs and system prompts are JSON strings. The base preparer passes the input and its own system prompt to the base call, which assembles them into one JSON string. The base checker accepts if that string is valid and its parts are unaltered copies; otherwise it loops back with a report. The base preparer and checker are built-in calls the runtime supplies ("within the base primitive it's all wiring"). The base checker can only be used with the base call. As an opening position, every other checker is a primitive; whether there will be other base calls or checkers is open.

**Lens 1: two kinds of boundedness.** "Bounding the nesting" conflates two questions.

- *Structural*: is every chain a finite term? Read as a grammar (primitive = prepare, call, check; slot = chain; chain = primitives), the definition needs a production that does not require another instance of itself, as an inductive definition needs a base case. The base primitive is one such production; a slot filled directly by a call would be another. Given one, a written spec is finite unless a named chain can be used inside its own definition, directly or by being passed into its own slots. So the principle may reduce to one question: may named chains be self-referential? Dhall, a total configuration language, says no.
- *Dynamic*: does a run stop? Loops come from the checker going round again, so this is about the retry limit, not nesting. Total functional programming (Turner) and "fuel" are the formal treatments. Retry limits multiply with depth (three retries at each of three levels is up to 27 calls), which argues for a budget passed down the nest rather than a separate limit per primitive.

**Lens 2: signatures.** Roughly:

```
prepare : (Input, Steer, Feedback?) → CallInput
call    : CallInput → Result
check   : (Input, Result) → Accept(Output) | Retry(Feedback) | NotPossible
```

The preparer transforms data; its output can be any type. The checker classifies; its output has a fixed three-way shape and decides what happens next. The preparer is data flow, the checker is control flow. Candidate consequences, none yet agreed:

- *The primitive is a loop*: repeat (prepare, then call) until check accepts. Category theory calls this Elgot iteration, a step of type `X → Done + Continue`, which is the checker's shape. The primitive may then not be primitive: it could be a loop pattern built from calls plus sequential and conditional chains, which would make chains finite trees whose leaves are calls.
- *The preparer must accept Feedback*, so the two slots are linked by a type and cannot be filled independently.
- *The checker probably needs the original input*, not only the result, to judge faithfulness.
- *A checker chain must end in a verdict.* Open: when a chain inside a check slot returns "not possible", is that a rejection or an outer "not possible"?
- *Checkers are where accountability lives.* The README promises to show "which decisions were a person's and which were the AI's". Those decisions are verdicts; a human approval is a checker filled by a person; the run record's key entries are verdicts and who made them; the policy checker's paths branch at checkers.
- *Pressure on the README.* "The model only fills in content" needs qualifying: a model-backed checker makes a control decision, though only among declared verdicts.

**Two further lenses, not yet used.**

- *Worked examples*: express echo, a model call with a schema check, a review loop, a human approval and one step of myelin's ADR loop in the concept, and note where each fits awkwardly.
- *Invariants first*: state what eshr must guarantee (every run ends; every path is visible before the run; every decision is recorded with who made it) and derive the constraints each forces.

**Prior art noted in passing.** Arrows and selective applicative functors (Mokhov et al., 2019) for statically analysable composition with branching; Dhall, CUE and Starlark for total configuration languages; algebraic effects for "computation only in calls"; nominal typing for named types; exhaustiveness and overlapping patterns for the compile-error rule; Erlang/OTP supervision for retry limits and escalation to a parent; design by contract for the check; Temporal for record and replay; AWS Step Functions (Retry, Catch), DSPy (signatures, assertions that retry with feedback) and BAML as working relatives. These were given from memory and are unverified.

## Open questions

- May a named chain refer to itself, directly or through slot filling? If not, is structural bounding settled?
- Is the base primitive the right terminating production, or should a slot be fillable directly by a call?
- Is prepare → call → check primitive, or a loop pattern built from calls and chain combinators?
- Are retry limits per primitive, or a budget passed down the nest?
- What are the preparer's and checker's input and output types, and is Feedback part of the preparer's input type?
- What does "not possible" from inside a check slot mean to the outer primitive?
- How should the README's "the model only fills in content" be qualified for model-backed checkers?
- What does the asymmetry imply for the policy checker and the run record?

## Next steps

- Start with the self-reference question (lens 1); it may settle structural bounding on its own.
- Work through the signatures (lens 2) and test them against the worked examples.
- Then revise ADR 0001's primitive section from this note on the PR #5 branch; the rest of the ADR looks unaffected.
- Optionally, verify the prior art and capture it separately.
