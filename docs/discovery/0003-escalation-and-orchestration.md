---
title: How should myelin escalate to a human, and does it need an orchestrator?
status: in-progress
date: 2026-09-24
---


# How should myelin escalate to a human, and does it need an orchestrator?

> **Imported from myelin, 2026-11-06.** Copied from `communitiesuk/myelin` `docs/discovery/0003-escalation-and-orchestration.md` at `4507d27`. It is a copy, not a link: eshr does not depend on myelin's files. References to ADRs, issues (`#NN`), plans, skills and `[[...]]` backlog items are to myelin's, kept as provenance. Note numbers differ: myelin's discovery notes 0003, 0005 and 0006 are eshr's 0003, 0004 and 0002.

## Problem

ADR 0003 decided that an agent lands its own work by default and
deferred the question of when it must escalate to a human instead
("the gate later carves out when it must escalate"). That deferred
question was framed as a **landing gate**: a rule, enforced at
`gh pr merge`, deciding whether the agent may merge its own work or
must hand it to a human.

This session set out to design that gate and instead concluded the
gate framing is the wrong one. The question underneath it — *when does
work need a human, and how does that get enforced?* — is real, but it
is not a merge-time question, and answering it well appears to require
an architectural change to myelin. This note records how far the
thinking got. **It is not close to a decision.**

## What we've covered

### The landing gate is a blind alley as a standalone target

Not refuted — *subsumed*. Two things were wrong with it:

- **Wrong moment.** The situations that actually need a human fire
  *during* the work, not at the merge. By the time you reach
  `gh pr merge`, either the problem was caught upstream or it was never
  a merge-time problem.
- **Wrong altitude.** "May this land itself?" is not a gate you design;
  it is an *output* of a more general capability. Given something that
  can escalate mid-flight, the landing answer falls out for free —
  landing is just the most common place a verdict gets consumed.

The thread's real payoff was diagnostic: it was the fourth signal
pointing at an orchestrator (see convergence, below), and following it
is what surfaced the architecture.

**One small piece survives independently:** the *enforcement plumbing*
at the merge point — rule 11's by-kind routing (an ADR or a `Revises`
branch goes to a human) plus a deterministic `PreToolUse` hook that
refuses a merge lacking a verdict. That is buildable and useful
regardless of the larger architecture, because something must enforce
whatever a judge decides and the merge command is a genuinely
deterministic signal. It is downstream of and subordinate to the
decision, not where the decision is made — do not discard it with the
blind-alley framing.

### Four kinds of "this needs a human"

Surfaced as the real triggers, sitting on different axes and firing at
different times:

1. **The decision is wrong, discovered downstream.** An agent
   struggling to implement a human's decision may be evidence the
   decision needs revising. Escalates *upward* to revisit the ADR —
   feeds [[Formalize the revision process end to end]] and ADR 0004's
   revision machinery, not a landing gate.
2. **Irreversible / high blast radius.** Altering a shared resource,
   deleting data, damaging another project. Fires *before* the
   dangerous action, at any point in the work.
3. **The decision is silent, not wrong.** The agent hits a fork the ADR
   never anticipated and cannot resolve it from the decision. Not
   "revise" — "you didn't say; choose."
4. **The reviewers are uncertain or disagree.** "Confidence not earned"
   in its most literal form, and the trigger closest to a mechanical
   read.

Cost/credit thresholds and security-surface triggers were considered
and folded into (2) rather than listed separately.

### A candidate architecture: interlocutor / worker / observer

The human's picture, recorded as the candidate to probe, **not** as a
decision:

- **Interlocutor** — the agent the human talks to. Interprets intent,
  explains what is going on, decides which skills apply. Loads
  *conversational* skills itself (e.g. `facilitated-discovery`, which is
  about how it talks to the human); *launches a worker* for anything
  that is not talking to the human (drafting, coding, ADRs).
- **Worker subagent** — given a prompt and the relevant skills
  (git-workflow, adr, …), does one task.
- **Observer subagent** — launched paired with the worker to watch it
  and raise a block.
- **Containers** — workers (and perhaps observers) run sandboxed, to
  bound blast radius.

The escalation capability the human is reaching for is: *the ability to
impose a block, in response to behaviour, that must be resolved before
work continues.* A block is therefore a first-class, durable object —
work suspends, the reason persists, a human resolves it. That is the
same object as the escalation queue in [[Reviewers]] / [[Ticket skill]]
and the reason plan steps would need to become **suspendable** (a
plan-schema consequence).

### Observer and container cover different triggers — they are not redundant

The sharpest result of the session:

- **(2) is point-in-time.** An observer that watches-then-reacts is
  structurally *too late* for an irreversible action — it has already
  happened. What stops (2) is making it *impossible* (a container) or
  refusing it *synchronously before it runs* (a `PreToolUse` hook), not
  observing it. So **(2) → container + hook.**
- **(1), (3), (4) are trajectory-level.** You catch them by watching a
  pattern over time, and a slightly-late block costs nothing because
  nothing irreversible is in flight. So **(1)(3)(4) → observer.**

This partition dissolves the observer's hardest feasibility problem: it
no longer needs to interrupt in real time. It also fixes the
"who watches?" problem — a separate observer does not depend on the
worker (the thrashing or reckless worker is the one least able to
police itself).

### Convergence: this is the orchestrator turn

The landing gate is the *fourth* parked thread asking for the same
thing — an orchestrator running workers under supervision, rather than
a set of skills a single agent loads:

- [[Use subagents to enforce skill use]] — orchestrator instead of
  skills chaining themselves via artefact reminders.
- [[Skill/subagent builder]] — the deferred skill-building "harness".
- [[ADR <-> plan loop as HTN]] — the orchestration graph.
- This note — supervised execution and escalation.

The real weight of the landing-gate work is that it makes the
orchestrator question concrete and forces it.

This note is the orchestrator's *control plane* — when work needs a
human, who supervises, how a block is imposed. Its *data plane* — what
a handover between steps carries, and how that context is compressed,
logged and measured — is developed separately in
`docs/discovery/0005-compression-and-handover.md`. The two meet where
the interlocutor hands a worker "the relevant skills" (that note's
codebook/context-assembler is a candidate mechanism for the handover,
and reframes probe 1) and where the enforcement piece needs somewhere
to read a verdict from (that note's per-handover log).

### [2026-09-25] Inherited from ADR 0006: the ticket store's deferred half

`docs/adr/0006-where-do-captured-ideas-live.md` (proposed) answered the
`Ticket skill` roadmap item with a deliberately small v1: seeds live in a
user-owned store located by an optional pointer, agents read but never
write that store, and a *developed* capture is a discovery note rather
than a new object. It did **not** build a ticket system, and it named
this note as where the rest belongs. Three capabilities were deferred
into this question, each with the trigger that revives it:

- **Escalate-don't-thrash** — the defined route for an agent that hits a
  human-needs-to-decide wall. This *is* the escalation queue above (the
  "same object as [[Ticket skill]]"), and the block-as-first-class-object
  the interlocutor/worker/observer picture is reaching for. Trigger: plans
  parallelising, so subagents run with less supervision than the present
  human provides.
- **Pick-up and triage** — an agent reading the next item and deciding
  ready-to-implement versus needs-a-conversation. Same era.
- **A platform-abstraction module** — routing tickets to org / host
  issues / JIRA by type, the same shape as ADR 0003's git host module,
  not a new subsystem.

So the ticket work does not compete with this note; its deferred half
*is* this note's escalation/orchestration question, and the eventual ADR
here should discharge it rather than treat it as separate. ADR 0006
carries a `Derives-From` to this note for that reason.

### [2026-10-14] Committed: the question is how, not whether

The maintainer has committed to the orchestrator turn. myelin is going
to move beyond skills that a single agent loads, and soon. That settles
the first of the "larger and not yet decidable" questions below. What
remains is the *shape*, and this note is now about how.

It also changes what the two probes are for. They're no longer
conditions to meet before an ADR. They're inputs to the design, and
they'll be answered in practice rather than as standalone experiments:

- **The first step is stage reviews (#77).** Before the next stage
  consumes an artefact, an independent reviewer subagent checks it, the
  parent sorts the findings and escalates decisions to the human, and
  the loop repeats until a stop rule is met. For plans, a drafter
  subagent writes and a reviewer subagent reviews. That is the
  interlocutor/worker split at its smallest, with the reviewer run
  *after* the worker rather than as a peer watching it, which is the
  parent-led shape probe 2 suspected the harness supports. Its run logs
  (whether workers followed their skills, rounds, overrides, models)
  answer probe 1 on real work.
- **An inventory of the harness's primitives (#78)** answers the rest:
  agent definitions (and whether they can preload skills), background
  agents, hooks, the SDK.
- With those in hand, this note goes back through facilitated-discovery
  aiming at the "how" ADRs (#79). The sequence is tracked in the pinned
  roadmap issue (#80).

The stage-review loop also gives the enforcement piece above somewhere
to read a verdict from: findings and how each was handled, recorded in
the PR.

### [2026-10-27] A candidate shape: one single-turn primitive over a context assembler

Worked through with the maintainer, developing the control plane
against the data plane (`0005`) and the Phase 2 stage-review evidence.
A candidate architecture, not a decision; recorded so the "how" ADRs
(#79) can draw on it.

**The evidence that reframed it.** Mining the Phase 2 stage-review runs
(ADRs 0008/0009/0004, plans 0010–0015) — whose records live only as
commit-message bodies in git history, there is no run-log store —
showed the loop's failures were **not** skill-loading failures. Probe 1
(below) was already designed around: ADR 0008 hands each worker its
governing skill *as an input* (the reviewer brief at
`skills/<skill>/references/review.md`), so adherence never rode the
probabilistic Skill-tool trigger. Every breach the records show instead
was a **handover/context-assembly failure**: a drafter resumed with its
own context rather than a fresh assembled one; a closing pass that
dropped a recorded decision; a fresh drafter that could not see the
review because the record did not quote it. The common root is a lossy
or mis-assembled worker input — exactly `0005`'s thesis, now with a
corpus.

**One primitive, two altitudes.** Everything is a single turn over
context assembled by `0005`'s context assembler (CA): a **worker**
takes a validated input and emits an artefact or performs one action;
an **orchestrator** takes assembled run-state and emits a dispatch
decision. Same shape, differing only in whether the output is an
artefact or a dispatch, and recursively composable (an orchestrator
node's children can be workers or further orchestrators — the
"team of agents per artefact-producing step"). The move underneath is
**persist the state, not the process**: the run is long-lived as
repo/pool state, no agent process is. An orchestrator decides what is
ready, fires it, and exits; an event (a worker completing, a human
resolving a block) re-invokes it over freshly assembled state.

**The keystone rule.** *A worker is one LLM call or one deterministic
action — never a tool-use loop. Anything that resists is decomposed
into more DAG nodes* (e.g. ADR 0008's plan reviewer, which must *run*
the plan's checks, splits into a deterministic action node that runs
them and a single-turn node that judges the result). This rule is
load-bearing: single-turn workers are what make the record granularity
align (turn = step = handover), collapse the observer problem, and let
parallelism be derived. Its falsifier is explicit: **the first task
that genuinely resists decomposition breaks it.**

**What the single-turn shape resolves here:**

- **Probe 1** is pre-empted, not merely unmeasured: the skill is
  injected as context, so the question is adherence-to-handed-context,
  which is `0005`'s handover problem, not a loading problem.
- **Probe 2** largely dissolves. A one-turn worker has no mid-flight for
  a sibling to watch. The trajectory that triggers (1)/(3)/(4) need
  moves up to the **DAG** — a sequence of worker outputs inspected
  *between* steps by the orchestrator/CA, which it does anyway. The
  "observer" becomes the orchestrator's between-step inspection, not a
  paired peer.
- **The block becomes an exit, not a new mechanism.** Work suspends
  because the orchestrator exits with nothing ready; the reason persists
  in the pool; an event resumes it. The "suspendable plan step" is the
  default, not a schema feature to build.
- **The orchestrator is mostly deterministic** — a repo-probe over typed
  state (any ready nodes? any High open after round 3? stop rule met?).
  An LLM turn is needed only for genuinely fuzzy judgement, and that is
  itself dispatched as a single-turn worker. So what is built is a
  deterministic workflow engine plus single-turn LLM nodes, not "an LLM
  that orchestrates."

**Parallelism is derived, and demoted.** If every worker declares its
inputs and outputs, the DAG — and the parallelism in it — falls out of
the contracts rather than being drawn. But the parent currently papers
over lossy handover by catching breaches live; parallelism removes the
parent, so a lossy handover that merely annoys serially goes silently
wrong in parallel. So **self-contained handover comes first; parallel
execution is the later payoff**, not the way in.

**Where this sits as a bet.** The whole thing concentrates risk in the
CA, which this reframe makes load-bearing for both planes (see `0005`
[2026-10-27]). The commitment is to use it until it works, with its
logs as the iteration mechanism. Because this is a big enough bet to
need its own ADR(s), and those ADRs will be revised as the CA iterates,
the sequence is **history skill (0001) → revision process (#92) → the
harness ADR** — the skills built *just good enough* to unblock and
iterate the harness, as the on-ramp that earns the right to bet, not a
deferral of it.

## Open questions

Two are decisive and directly **probeable** on the current harness;
answer them before any ADR. *(Both are reframed by the [2026-10-27]
entry above: probe 1 is pre-empted by injecting the skill as context,
and probe 2 largely dissolves under single-turn workers — a one-turn
worker has no mid-flight to observe.)*

1. **Does delegating to a worker make skill-use reliable, or just move
   the trigger problem down a level?** The architecture assumes the
   interlocutor can hand a worker "the relevant skills" and the worker
   will load and follow them. But a spawned worker still has to *load*
   git-workflow/adr — the same probabilistic trigger as
   [[Framework to test whether a skill gets loaded]]. If a worker
   launched with "use git-workflow" reliably obeys, that is a large win
   and quietly resolves much of [[Use subagents to enforce skill use]].
   If not, the orchestrator buys structure but not enforcement. Not yet
   measured.
2. **Can a sibling observer actually *see* the worker and *impose* a
   block, given this harness's subagent model?** The model here favours
   workers that *return a result to a parent*, not workers that
   *broadcast tool calls to a peer*, and gives stop-control to the
   parent, not to siblings. If a peer observer cannot observe or halt,
   the "observer" is really a *function of the interlocutor* (launch the
   worker in the background, watch its output, stop it) or a hook —
   *not* a paired peer subagent. Whether the pair-of-agents picture maps
   onto the harness primitives is unproven.

Larger and not yet decidable:

- ~~**Is myelin taking the orchestrator turn at all?**~~ Settled
  2026-10-14: yes. The eventual ADRs decide its shape, not whether to
  take it (see above).
- **What does the observer read to judge (1)(3)(4)?** The worker's tool
  calls, its outputs, the diff, the governing ADR? And what is the
  structured form of a "block" so the interlocutor/human can act on it?
- **Container boundary vs git.** A sandboxed worker still needs to push
  and open PRs, so credentials cross the boundary — a container holding
  push access to a shared remote is only partly contained. How the
  worktree/dependency bootstrap (ADR 0003's `.venv`/`node_modules`
  split) works inside a container is unresolved. Connects to
  [[Azure container skills]].
- **Relationship to the harness's own gates.** The harness already
  gates dangerous commands via its permission layer — but by *command
  pattern*, not by understanding blast radius, and (observed
  2026-09-24) *non-deterministically*: it refused `gh pr merge` on
  2026-09-23 and allowed it on 2026-09-24 with no valid explicit
  permission. A myelin blast-radius guard would be a second layer over
  an unreliable one. Whether myelin replaces, wraps, or defers to the
  harness gate is open. A **second** harness gate is now confirmed by
  observation: editing `.claude/settings.local.json` to grant the
  landing permission was refused as `[Self-Modification]` (2026-09-24).
  So the permission decision is irreducibly the human's — the agent
  cannot grant itself the right to land, whatever the orchestration
  design. Any observer/hook machinery must therefore operate *within* a
  permission boundary it cannot alter, and escalation-to-human is not
  merely a policy myelin chooses but a harness-enforced floor it builds
  on top of.

## Next steps

- **Probe 1 (skill-loading in workers).** Launch a subagent with an
  explicit instruction to use git-workflow on a trivial artefact and
  measure whether it loads and follows. Cheap; no credits beyond the
  run. This is also material for
  [[Framework to test whether a skill gets loaded]].
- **Probe 2 (observer feasibility).** Establish what one subagent can
  observe of another and whether it (or the parent) can halt it, from
  the harness/SDK capabilities — before assuming the paired-observer
  picture is buildable.
- ~~**Do not** open an ADR until both probes are answered; the
  architecture rests on them.~~ Superseded 2026-10-14: the probes are
  now answered by the stage-review loop (#77) and the harness inventory
  (#78), and the stage-review ADR goes ahead first, as the smallest
  piece of the architecture. The "how" ADRs still wait for that
  evidence.
- **Reframe [[Reviewers]]** so its landing-gate material becomes input
  to this question rather than an active thread of its own, matching the
  reclassification above.
- The small enforcement piece (rule 11 routing + a merge-verdict hook)
  can be specified independently if a merge gate is wanted before the
  architecture lands — but note it has nowhere to read a verdict *from*
  until a judge exists.
