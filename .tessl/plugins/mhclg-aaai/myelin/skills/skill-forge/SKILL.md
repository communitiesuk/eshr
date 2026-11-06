---
name: skill-forge
description: The mandatory workflow for authoring a new skill in any project the user works in. TRIGGER on any task that involves writing a new skill (a new `skills/<name>/SKILL.md` artifact — new capability, new trigger contract). SKIP for edits to an existing skill body, doc-only changes, and tasks that write executable code without a new skill (use the `test-first-workflow` skill for those). Enforces frontmatter first, then a failing eval scenario, then the skill body. The eval scenario is the contract.
---

# Skill-forge

Use this whenever you're about to author a new skill. It is the standing rule for how new skills get written. The three phases below are mandatory and ordered — do not skip, do not merge, do not reorder.

This skill is the analogue of `test-first-workflow` for code: docstrings → failing tests → code becomes frontmatter → failing eval scenario → skill body. The two skills are siblings; if you know one, the shape of the other is already familiar.

## Phase 1 — Frontmatter first

Before writing any of the skill body:

- Create `skills/<skill-name>/SKILL.md`. The directory name is the skill name; it must match the `name:` field verbatim.
- Author the YAML frontmatter — `name` and `description` — and nothing else. The body below the frontmatter is a placeholder H1 or a single-sentence stub; no rules, no anti-patterns, no phases yet.
- The `description` is the **trigger contract**: it is what the description-matcher uses to decide whether to load this skill. Treat it the way `test-first-workflow` treats a docstring — force yourself to specify what this skill is for, in prose, before writing any of its content.
- The description should follow the shape the existing skills use: one sentence naming what the skill governs, a `TRIGGER on ...` clause naming the concrete task shapes that should load it, and a `SKIP for ...` clause naming the near-neighbour shapes that should not.

Commit the frontmatter on its own if the scope is non-trivial. The point: force yourself to specify the trigger contract before writing the failing scenario or the skill body.

## Phase 2 — A failing eval scenario, hand-authored

Write the eval scenario against the frontmatter. The scenario is the executable contract; the skill body will be judged against it.

- Create the directory `evals/<skill-name>-N/`, where `<skill-name>` matches the target skill's directory name under `skills/` and `N` is the highest existing scenario number for **this** skill plus one, starting at `0` if none exist. Per-skill directory naming confines merge collisions to the legitimate case (two branches independently adding a scenario for the same skill) and keeps disjoint work in disjoint namespaces.
- Populate the directory with `task.md`, `scenario.json`, and `criteria.json`. `criteria.json` should be a `weighted_checklist` in the same shape as the existing scenarios under `evals/`.
- **Author this by hand. Do not use `tessl scenario generate`.** Generation runs remotely against an uploaded plugin and materialises only via a subsequent `tessl scenario download`. It cannot occupy the "failing-test-before-body" slot because the body is what you have not written yet. `tessl scenario generate` has a legitimate use as a post-forge coverage-broadening step — see the section on that below — but it is never the mandatory Phase 2 step.
- The scenario describes the **smallest concrete behaviour** the skill must eventually satisfy. Not the full behaviour of the skill; one specific, testable slice.
- Review each checklist item against this list before proceeding to the body:
  1. Would a plausible-but-wrong skill body still pass this check? If yes, tighten the assertion.
  2. Does the check exercise a behaviour the skill's rules actually govern, or only a shallow structural property (frontmatter presence, section headings)?
  3. Is the check specific enough that "the skill is missing" would clearly fail it?

Commit the scenario on its own (a red commit — this scenario is expected to not yet pass). The scenario **is** the improvement queue: because `tessl eval run` has no scenario-selection flag, every subsequent run picks it up automatically.

## Phase 3 — Skill body until review passes

Write the skill body. Iterate on the body, running `tessl review run <skill-path>` on each pass, until review is green.

- The body must speak in the same voice as the description. Do not paraphrase the trigger contract — either the description or the body is wrong if they disagree.
- Mirror the tone and section structure of the existing hand-written skills (`skills/adr/SKILL.md`, `skills/plans/SKILL.md`, `skills/test-first-workflow/SKILL.md`, `skills/facilitated-discovery/SKILL.md`) where it fits. Body typically includes: what the skill governs, mandatory phases or rules in order, a "Do not" / anti-patterns section, and a "When you may deviate" section if applicable.
- Do not modify the eval scenario to make review pass. **The scenario is the contract**: if the body drifts from the scenario's target behaviour, the body is wrong, not the scenario. (If you can prove the scenario itself is invalid — e.g. it asserts a behaviour the ADR that authorised this skill explicitly rejects — you may edit it, and must state the reason explicitly in the commit message.)
- Re-run `tessl review run <skill-path>` after each substantive edit. It is cheap.

Commit the body on its own once review is green.

## Exit criteria — asymmetric

- **`tessl review run` must pass.** It is cheap, and it is the structural sanity gate: frontmatter well-formed, trigger phrasing coherent, body plausible enough to be worth running. Blocking on review costs almost nothing.
- **The eval scenario must exist. It need not pass.** The failing scenario captured in Phase 2 *is* the improvement queue. Because `tessl eval run` has no scenario-selection flag, every subsequent eval run automatically picks the new scenario up. No provisional status flag, no `skills/_review/` queue directory, no separate ticketing. "Improve later" concretely means: come back and make this scenario pass.

At the point the two criteria above are met, hand control back to the caller. The enclosing work — whatever prompted the skill to be written — proceeds. Do not block the caller on making the eval scenario pass; that is legitimately deferred work.

## Optional post-forge coverage broadening

Once the skill body is green under review, `tessl scenario generate` (followed by `tessl scenario download --strategy merge`) may be used to broaden scenario coverage. This is a deferred improvement step, not part of the mandatory workflow — the two-step remote-then-download dance would otherwise block the caller.

**Gate this step on a review-green skill body, not on frontmatter alone.** An empirical probe (a `tessl scenario generate -n 1` run against a stub skill — frontmatter plus a one-line body — versus the same command against a skill with a substantive rules-and-anti-patterns body) established that generation against a stub yields checklists of shallow structural checks that repeat the same behaviour with different inputs, adding no coverage beyond a single scenario. Generation against a substantive body yields checklists whose items directly probe the skill's stated rules (e.g. "uses `str.casefold` not `str.lower`", "raises `TypeError` for `None` inputs") and are meaningfully complementary to a hand-authored scenario. Do not invoke `tessl scenario generate` before Phase 3 is complete.

## Known behaviour of `tessl scenario download --strategy merge`

An empirical probe established that the deduplication key used by `tessl scenario download --strategy merge` is the **directory name under `evals/`**, not the scenario `description` and not a content hash.

- If a local directory shares its name with an incoming downloaded scenario (e.g. both are called `scenario-0/`), the incoming scenario silently overwrites the local one — `task.md`, `scenario.json`, and `criteria.json` are all replaced.
- If a local directory has a different name from every incoming scenario but shares its `description` with one of them, both survive. Local directory is untouched; incoming scenario materialises under its own tessl-assigned name (typically `scenario-N/`).

Two operational consequences:

- The per-skill `<skill-name>-N/` naming rule mandated in Phase 2 keeps hand-authored scenarios in a disjoint namespace from downloaded ones (tessl downloads use `scenario-N/` by default), so a merge after a `tessl scenario generate` on your skill will not clobber the hand-authored Phase 2 scenario for the same skill.
- If two branches independently add a scenario for the **same** skill and pick the same `N`, a merge will clobber one of them. This is the legitimate collision case; reconcile by hand.

## When you may deviate

- **Editing an existing skill body without changing its trigger contract**: this skill doesn't apply. Edit the body and re-run `tessl review run <skill-path>`.
- **Changing a skill's `description` (retriggering)**: treat as authoring a new skill from Phase 1. The description is the trigger contract; changing it changes the contract.
- **The user explicitly says "just write the skill" or "no eval needed"**: follow their instruction, but note the deviation in your reply. The skill will ship without an improvement queue.

## Anti-patterns to avoid

- Writing the skill body before the eval scenario (the contract wasn't red first — you're checking what you wrote, not what you specified).
- Using `tessl scenario generate` as the Phase 2 step. It cannot occupy that slot — it needs the plugin uploaded, runs remotely, and materialises via a separate download step.
- Editing the eval scenario to make a passing body look complete, without explicit justification.
- Writing eval assertions loose enough that a plausible-but-wrong skill body passes them ("skill exists" instead of "skill body enforces rule X").
- Blocking the caller on making the eval scenario pass. The asymmetric pass criteria exist so the caller's enclosing work can proceed; the failing scenario captures "improve later" as executable work.
- Retrofitting scenarios for pre-existing skills as part of this workflow. That is a separate exercise with its own trade-offs, not something to fold silently into a new-skill-authoring step.
