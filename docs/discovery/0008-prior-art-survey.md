---
title: "Probe B4: does something already do this?"
status: in-progress
date: 2026-11-09
---

# Probe B4: does something already do this?

## Problem

Note 0002 §7 sets out stopping tests: reasons to stop work on eshr before building it. Hard blocker B4 (§7.2) asks: "Does something already do this, and is it available?"

**Available** means usable without a procurement process: an open or freely usable licence, runnable in our own environment. A tool that needs government procurement counts for much less.

*Stop or change course if* an available tool gives most of the value. That might mean building on it rather than stopping.

## What we've covered

**Method.** A research subagent ran a survey of roughly one hour on 2026-11-09. Licences and recent activity came from the GitHub API. Features came from each tool's documentation and papers; sources are listed below. Items not checked are marked "unverified" or "inferred" and listed under open questions.

**Verdict: the stopping criterion is not met.** No available tool gives most of eshr's value.

- **Available, but no security semantics:** LangGraph, Pydantic AI / pydantic-graph, Microsoft Agent Framework workflows, Haystack, Burr, Open Agent Spec, DSPy, BAML, Temporal. Together they cover model calls, typed outputs, branching on typed returns, graph execution, checkpoints, replay and durability.
- **Security semantics, but not a usable base:** CaMeL and FIDES are runtime-only research code. Progent, Invariant and TaintGate-style tools are runtime monitors around open loops: guards in §2's sense. Agentproof checks graphs statically, but has no labels or effects, and no code was found.
- **Nothing found combines** a declarative hybrid graph, runtime-owned control flow, IFC labels with first-class endorse and declassify, and a static check on the flattened graph.

### Comparison

Columns: **Ctl** = control flow owned by code; **Typed** = typed outputs or closed tool choice; **IFC** = information-flow labels; **Static** = static check before the run; **Replay** = record and replay.

| Candidate | Licence / availability | Ctl | Typed | IFC | Static | Replay | Notes |
|---|---|---|---|---|---|---|---|
| CaMeL (google-research/camel-prompt-injection) | Apache-2.0; research artefact, no support planned; last push 2025-06-20 | Yes, per run: privileged LLM writes a restricted-Python plan, custom interpreter runs it | Partly: quarantined LLM returns structured values; tools called from generated code, not a closed sum | Yes, at runtime: capabilities and provenance on values, policies at tool calls | No | "Replay-with-policies" mode for AgentDojo | Closest security semantics. README warns the interpreter "likely contains bugs" and "might not be fully secure". Tied to AgentDojo. |
| FIDES (microsoft/fides) | MIT; 5-commit tutorial notebook; last push 2025-05-30; set up for Azure OpenAI with Entra ID | Planner loop with IFC | Not a library | Yes, at runtime: confidentiality and integrity labels, hiding primitives (paper) | No (dynamic taint) | No | Concept reference only. |
| Progent (sunblaze-ucb/progent) | MIT; research code | No; wraps an existing agent | No | No; privilege policies over tool calls | No | No | Narrow scope. |
| Invariant Guardrails (invariantlabs-ai/invariant) | Apache-2.0; runs locally; last push 2026-01-12, possibly going stale | No; proxy or check layer | No | No labels, but rules can match sequences such as ToolCall -> ToolCall (trifecta-like) | No; live traffic or trace analysis | Offline trace analysis | A guard, not constraint by construction. |
| TaintGate (two repos), interbolt, Tessera | MIT (TaintGates); hobby-scale, 0 stars | No (gateway or monitor) | No | Runtime taint | No | No | The idea is in the air; not viable. |
| Agentproof (arXiv 2603.20356) | Paper only; no code found | Analyses graphs extracted from LangGraph, CrewAI, AutoGen, Google ADK | n/a | No | Yes: six structural checks, plus temporal policies compiled to finite automata | Runtime trace checking | Nearest prior art for the static checker. No labels or effects. Not available. |
| Open Agent Spec (oracle/agent-spec; WayFlow runtime) | Apache-2.0 or UPL-1.0; last push 2026-10-28 | Yes for Flows (control and data edges); also has an Agent (ReAct) component, an open loop | LlmNode and ToolNode with JSON-Schema I/O; BranchingNode on a value-to-branch map; MapNode | No | Schema conformance and edge checks only | Runtime dependent | Closest to eshr's declarative spec format. Adapters to LangGraph, AutoGen, CrewAI. No labels, effects, guard or checker. |
| Pydantic AI / pydantic-graph | MIT; very active | Yes (graph) | Strong: edges inferred from a node's return-type union (`A \| B \| End[T]`), close to branching on a typed sum; return types enforced at runtime | No | No documented pre-run validation | Durable execution via Temporal, DBOS, Prefect or Restate, journalling model and tool calls | Good substrate for typed calls and durability. |
| DSPy | MIT | Your own Python | Signatures give typed I/O. In 2.6, Refine and BestOfN replaced Assert and Suggest: N tries, a reward function and a threshold; Refine adds LM-written feedback (close to a guard) | No | No | Caching and tracing | Feedback is free text, not an enum `Retry<Reason>`. Focus is prompt optimisation. |
| BAML | Apache-2.0; compiler and runtime local, no account (inferred; Boundary Studio SaaS optional) | Calling code | Strong: typed functions, union and enum returns, schema-aligned parsing, parse errors with raw text; retry is transport-level | No | Compile-time type checks of function schemas only | No | Extra DSL and code generation. |
| LangGraph | MIT; self-hostable (in-memory, SQLite, Postgres checkpointers); paid platform optional | Yes (StateGraph); nodes can be ReAct agents | User's choice; tool choice usually native tool calling | No | Structural `compile()` only (inferred). Agentproof shows third parties must extract the graph to check it | Checkpointing with "time travel" | Labels, effects and checker would be bolted on. |
| Microsoft Agent Framework workflows (successor to Semantic Kernel and AutoGen) | MIT | Yes (WorkflowBuilder graph); functional API too | "Type-validated message routing" between typed executors; declarative workflows | No | Edge type validation at build time (from docs; depth unchecked) | Checkpoints at superstep boundaries | Mature; aimed at multi-agent orchestration. |
| Haystack pipelines | Apache-2.0 | Yes (component DAG, capped loops, ConditionalRouter) | Typed sockets | No | Yes, for types: `.connect()` checks socket types before running | YAML serialisation; breakpoints and snapshots (unverified) | Precedent for static socket typing. Not security-oriented. |
| Burr (Apache incubating) | Apache-2.0 | Yes (actions and transitions) | Not a focus | No | No | Persistence, tracking UI, replay | Possible run-record UI. |
| Temporal | MIT; self-hostable server | Yes, in workflow code | n/a | No | No | Deterministic replay of workflow history (from memory) | Standard durability; heavy for a research instrument. |
| DBOS | MIT; Postgres-backed library | Yes | n/a | No | No | Durable step journal | Lighter alternative to Temporal. |
| Restate | GitHub reports NOASSERTION; believed BSL (unverified) | Yes | n/a | No | No | Journal | Check licence before use. |
| ControlFlow (Prefect) | Apache-2.0; archived 2025-08 | | | | | | Dead; excluded. |
| AWS Step Functions | Proprietary SaaS. **Not available** by our definition (AWS account and procurement) | Yes (Amazon States Language) | JSON paths | No | Validates definitions | Execution history | Reference point only. |
| Jif / FlowCaml / LIO | Jif latest 3.5.0, page dated 2016; FlowCaml long dead; LIO (Haskell) is dynamic | n/a | n/a | Decentralised labels (Jif) | Yes, for Java (Jif) | n/a | Not usable as components. The theory (lattice join, endorse and declassify, robust declassification) is reusable. A lattice check over a finite flattened graph is small to write. |

### Per candidate

**CaMeL** has the closest security semantics: capabilities and provenance on values, policies checked at tool calls. But it is a research artefact with no planned support, its authors warn the interpreter is buggy and may be insecure, and all checks happen at runtime. Its plan is generated code, not a declared graph.

**FIDES** has the label model eshr wants (confidentiality and integrity, hiding primitives), but the code is a five-commit tutorial notebook tied to Azure. Use the paper, not the code.

**Progent, Invariant and the TaintGate-style tools** wrap an open loop and police it at runtime. They are guards in §2's sense. Invariant's sequence rules come nearest to trifecta-style policies, but it does not constrain by construction.

**Agentproof** is the nearest prior art for the static checker: structural checks and temporal policies as finite automata over a graph. It has no labels or effects, and no code was found.

**Open Agent Spec** is the closest match to eshr's declarative spec format: typed LLM and tool nodes, branching on values, adapters to other runtimes. It has no labels, effects, guard or checker, and it also admits ReAct agents as nodes.

**Pydantic AI / pydantic-graph** infers edges from a node's return-type union, close to eshr's branching on a typed sum, and enforces return types at runtime. It has durable execution through Temporal, DBOS, Prefect or Restate. It has no pre-run validation and no security model. It is a good substrate.

**DSPy** gives typed signatures and Refine/BestOfN retry loops. Refine is close to a guard, but its feedback is free text, not an enum of retry reasons. Its focus is prompt optimisation.

**BAML** gives strong typed functions with union and enum returns and good parse errors. It adds a DSL and code generation. It is the alternative to Pydantic AI for typed calls.

**LangGraph, Microsoft Agent Framework and Haystack** are mature graph runtimes with code-owned control flow and checkpoints. Haystack checks socket types before running, a precedent for static typing; the others check structure or edge types at build time, depth unverified. None has labels or effects; they would be bolted on.

**Burr, Temporal, DBOS and Restate** cover persistence and replay. Burr's tracking UI could serve as a run-record viewer. Temporal is heavy for a research instrument; DBOS is lighter. Restate's licence needs checking.

**ControlFlow** is archived. **AWS Step Functions** is not available by our definition. **Jif, FlowCaml and LIO** are not usable components, but their theory is.

### Build on rather than from scratch

- **Typed LLM calls:** Pydantic AI (MIT). Its return-type unions match the closed-sum idea. BAML is the alternative.
- **Durability, if ever needed:** Temporal or DBOS through Pydantic AI's durable-execution integration. Start with plain code, as §7.3 says.
- **Spec format:** look seriously at Open Agent Spec (Apache-2.0) as a base or interop target before inventing one. At least borrow its node and edge vocabulary.
- **Security semantics:** borrow from CaMeL (Apache-2.0 capability and policy code) and FIDES (label model). Agentproof's graph-times-automaton approach can inform temporal policies in the checker.
- **Ladder comparison rungs:** an open loop plus an Invariant- or Progent-style runtime policy; CaMeL itself on AgentDojo.

### What remains novel

- A static type, label and effect checker over a flattened declarative hybrid graph, with trifecta-style policies as type errors and endorse and declassify as explicit nodes.
- The constrainedness profile (§6.9).
- The typed `guard`, with enum retry reasons and fail-closed failure variants in the language (§6.4, §6.8).
- The purpose: an instrument for the ladder experiment (§7.4).

Typed calls, graph runtime, replay and durability are commodity.

### Sources

- CaMeL: https://github.com/google-research/camel-prompt-injection ; https://arxiv.org/abs/2503.18813
- FIDES: https://github.com/microsoft/fides ; https://arxiv.org/abs/2505.23643
- Design patterns for prompt injection: https://arxiv.org/abs/2506.08837 ; https://simonwillison.net/2025/Jun/13/prompt-injection-design-patterns/
- Progent: https://github.com/sunblaze-ucb/progent (arXiv 2504.11703)
- Invariant: https://github.com/invariantlabs-ai/invariant
- TaintGate: https://github.com/guru-bharadwaj20/TaintGate ; https://github.com/shubham-jadhav-FiatLux/TaintGate
- RTBAS: https://arxiv.org/pdf/2502.08966
- Agentproof: https://arxiv.org/abs/2603.20356
- Open Agent Spec: https://github.com/oracle/agent-spec ; https://oracle.github.io/agent-spec/26.1.2/misc/reference_sheet.html ; https://arxiv.org/abs/2510.04173
- pydantic-graph: https://pydantic.dev/docs/ai/graph/graph/ ; durable execution: https://pydantic.dev/docs/ai/durable-execution/overview/
- DSPy: https://dspy.ai/current/tutorials/output_refinement/best-of-n-and-refine/
- BAML: https://docs.boundaryml.com/ref/llm-client-strategies/retry-policy ; https://docs.boundaryml.com/guide/introduction/why-baml ; https://docs.boundaryml.com/guide/baml-basics/error-handling.md
- LangGraph: https://docs.langchain.com/oss/python/langgraph/persistence
- Microsoft Agent Framework: https://learn.microsoft.com/en-us/agent-framework/concepts/workflows/ ; https://learn.microsoft.com/en-us/agent-framework/workflows/
- Haystack: https://docs.haystack.deepset.ai/docs/pipelines
- Burr: https://burr.apache.org/
- Temporal: https://github.com/temporalio/temporal
- DBOS: https://github.com/dbos-inc/dbos-transact-py
- Restate: https://github.com/restatedev/restate
- ControlFlow: https://github.com/PrefectHQ/ControlFlow
- Jif: https://www.cs.cornell.edu/jif/

## Open questions

Not verified by the survey:

- Whether Agentproof code exists.
- Restate's licence.
- How deep LangGraph's and Microsoft Agent Framework's build-time validation goes.
- Haystack's breakpoint and snapshot details.
- Temporal's replay details and DSPy's Signature semantics (from memory).
- CaMeL's internals (only the file layout was seen).
- Whether BAML works fully without an account.
- Jif's licence.

Decisions the survey raises:

- Should eshr adopt or extend Open Agent Spec's format rather than invent one?
- Should Pydantic AI be the model-call layer?

## Next steps

- Feed the "build on" list into §7.3's cost estimate and the ADR 0001 revision.
- Verify the unverified items before relying on them.
