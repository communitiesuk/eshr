# eshr
Extensible Scoped Harness Runtime

## Why this exists

### The problem

Today's AI agents run in an **open loop**: the model decides what to do, in what order, and when to stop. Controls are added from outside it, through permissions, sandboxes and review afterwards. That leaves three gaps, which matter most in government:

1. **They can't be assessed in advance.** Security and data-protection assurance assumes you can set out a system's behaviour and data flows before it runs. An open-loop agent decides them while it runs, so an assessor gets a model card and a system prompt rather than something they can review.
2. **Guards can stop things, but can't make them happen.** You can block "never push to main". You can't guarantee "always run the tests", "always update the docs" or "always stop for a human here". Today, those depend on a person watching.
3. **There's no reliable record.** It is hard to show afterwards what the AI did, on what information, and where a human stepped in.

### The hypothesis

eshr is a runtime for building harnesses. It can build an open loop as easily as anything else. What it adds is the ability to build **constrained (scoped) harnesses**, where the harness, not the model, holds the control flow.

The hypothesis is that a scoped harness can be assured *by design*, not only by containment, and will do the work at least as well:

- A declared graph sets out everything a run can do. Steps it does not declare are refused.
- The model only fills in content at a step. It has no tools, and its output is checked before anything uses it.
- Side effects happen only in ordinary code, which can be reviewed and tested.
- Each step's input and output are recorded, so a run can be audited and replayed.
- Humans come in at named points in the graph, rather than whenever the model decides to ask.

### The value, if it holds

- **Deployable where agents currently aren't.** Assessors get artefacts they already know how to review: a graph, its rules, and where each rule is enforced.
- **Defensible accountability.** It is clear which decisions were a person's and which were the AI's, with evidence to back that up for audit and for reporting on AI use.
- **Quality that doesn't depend on who is driving.** Required steps happen because the code calls them, not because someone remembered to ask.
- **Less exposure to prompt injection.** Injected text can affect only an output that is then checked. It can't choose actions. (It can still shape the content of permitted actions, so this reduces the risk rather than removing it.)
- **Lower cost.** Each step gets only the context it needs, so most steps can run on cheaper models, with frontier models kept for judgement.
- **Less lock-in.** The model is a part that can be swapped, not the thing in charge.

### What would prove it wrong

The hypothesis fails if assembling the right context for each step proves unreliable, if writing the graphs costs more than teams will pay, or if the checks become approvals that people wave through. These are to be measured, not assumed. The reasoning is in [`docs/discovery/`](docs/discovery/).
