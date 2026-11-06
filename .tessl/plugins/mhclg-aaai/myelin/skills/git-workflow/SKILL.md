---
name: git-workflow
compatibility: "Needs Bash and git, and the host CLI (gh for GitHub) where a remote exists. No model floor: measured 2026-09-28 with the script on deepseek-v4.1-flash, evals/git-workflow-0 100/100/100 (run 01a0e7ca-2dc2-74ee-8495-8200d2acacb1) and evals/git-workflow-1 100/98/94 (run 01a0e75f-1236-727c-a8db-f848fce7eb91), against bars of 87 and 86 (plan 0005 Step 6, plan 0009)."
description: Governs where work happens in a git repository and how it lands — branch-per-artefact, worktree isolation on contention, and integration that preserves commit structure. TRIGGER on any task about to create or modify a file in a git repository, before the first edit — a discovery note, an ADR, a plan, or code alike, all need a branch first. SKIP for read-only exploration that edits nothing, and for work already proceeding on an artefact branch this workflow created.
---
# Git workflow

Use this whenever you are about to create or modify a file in a git repository. It is the standing rule for **where** work happens and **how** it lands. Markdown decision artefacts — discovery notes, ADRs, plans — are work exactly as code is; treating a document as not really work is the usual failure. The mechanics are a script that ships with this skill; you run it at two moments and decide only what a model has to decide. Rationale is in `docs/adr/0003-git-workflow.md` and `docs/adr/0004-where-does-history-live.md`; the rules the script enforces are in `references/RULES.md`.

## Finding the script

The harness states this skill's base directory when it loads the skill. Call that `$SKILL_DIR`. The script is invoked with Bash, never by path alone:

```sh
bash "$SKILL_DIR/scripts/git-workflow.sh" --help
```

It needs git, and the host's command-line tool (`gh` for GitHub) where the repository has a remote. Its exit codes: 0 done; 1 stopped with a report; 2 usage or precondition failure, nothing changed; 3 stopped by design, a decision that a human merges.

## The two moments

**Before the first edit**, decide what the artefact is (Rule 2) and what its path will be, then:

```sh
bash "$SKILL_DIR/scripts/git-workflow.sh" begin <artefact-path>          # or --slug <slug> for work no skill governs
```

It prints `trunk=`, `branch=` and `dir=`. Work in `dir=` and nowhere else. It derives the trunk, isolates into a worktree when the checkout is not on the trunk or is dirty, names the branch from the path, copies the small configuration files, and ignores `.worktrees/`. `begin` also brings the local trunk current, or stops with a report; when it exits 1, relay the report in full and do not create the branch by hand. When it prints `include=<file>`, it has left that file changed and uncommitted: include it in the artefact's first commit. You have not begun the deliverable until it has run; if you are editing and cannot name the branch you are on, stop and run it.

**When the governing skill says the artefact is complete**, from inside `dir=`, with everything committed:

```sh
bash "$SKILL_DIR/scripts/git-workflow.sh" land
```

- **0**: it merged with two parents, cleaned up, and left the primary checkout where it was, or on the trunk where the work was in place, and the local trunk is current or a note says why not. Report the merge it printed.
- **3**: the branch adds an ADR or carries `Revises`, so it is a decision: it is pushed and proposed, and a human merges it. Say so, give the pull request and each `artefact:` link it printed (the ADR as it stands on the branch, for the human to read before merging), and stop.
- **1**: a host command was missing, failed or refused. Relay the report it printed in full: the pull request if one was opened, the command, the state left behind, and the permission hint. Do not merge locally, do not clean up, and do not describe the artefact as landed.
- **2**: a precondition failed, usually the trailer on the first commit or a dirty tree. Fix it and run `land` again.

Between the two moments, commit as the governing skill directs (Rule 3), and put the trailers where Rule 9 says.

## What you decide

### Rule 2 — One branch per artefact

An **artefact is what one skill produces in one invocation**:

| Governing skill | Artefact |
| --- | --- |
| `facilitated-discovery` | one discovery note |
| `adr` | one ADR |
| `plans` | one plan |
| `test-first-workflow` | one working code change |
| `skill-forge` | one skill |

**This skill never defines "artefact" itself.** The governing skill already defines its own boundaries and exit criteria. Do not invent a boundary here, and do not split or merge an artefact because it would make the branching tidier. Work governed by no skill is still an artefact and still gets its own branch, named with `--slug`.

### Rule 3 — Commit cadence is delegated

This skill never specifies what a commit contains. The governing skill decides, and the governing skills deliberately disagree with one another (`test-first-workflow`, `skill-forge` and `plans` each mandate a different cadence). The delegation is deliberate; do not tidy it up here.

### Rule 4 — Bookkeeping is not an artefact

**The test.** A change is **bookkeeping** when it has no independent truth condition: it is true only because some other work is true. A change that would still need to be made had the accompanying work not happened is **work**, whatever file it touches.

**The rule.** Bookkeeping does not get its own branch; it rides with the change that makes it true, on that change's branch. Bookkeeping with nothing to ride on has an independent truth condition — it is work, and it takes a branch like anything else.

**Classification is relational** — a property of the relationship between the change and the work in hand, never of the file it touches. The same line in the same file classifies both ways:

| Change | Classification | Why |
| --- | --- | --- |
| Adding `.worktrees/` to a repository's `.gitignore` as a deliverable implementing a decision to adopt this workflow | work | Independently true; independently verifiable. It is the point of the change, not a record of another. |
| The script adding `.worktrees/` to a target repository's `.gitignore` while creating a worktree | bookkeeping | Incidental to producing some other artefact. Has no truth of its own. |
| `weeknotes/` in `.gitignore`, added on its own account | work | Nothing else made it true. It should have had a branch. |

**The scope.** The exemption is from needing its own branch and from nothing else: bookkeeping is committed, reviewed and merged like any other change, and Rule 3 still decides what a commit holds. Apply the test by asking what makes the change true; "it is only bookkeeping" is not an answer.

### Rule 9 — Trailers: history is written for retrieval

Artefacts form a graph — a plan derives from an ADR, an ADR from a discovery note, a code change or a skill from a plan — and because completed artefacts leave the tree, that graph is recorded in git history as trailers on commits. **The graph is append-only**: exactly one commit adds an edge and carries the trailer for it. **The table is exhaustive**: an event not in it adds no edge.

| Trailer | On the commit that | Value |
| --- | --- | --- |
| `Derives-From:` | establishes that an artefact derives from another: the first commit on the artefact's branch, or a later commit that re-points it | path of the upstream artefact; one trailer per direct upstream |
| `Revises:` | changes what an accepted ADR decides | path of the ADR |
| `Clarifies:` | makes a non-revising edit to an existing ADR (typo, citation, metadata, or an uncaught cross-reference): a self-edge, as `Revises` is on an in-place revision | path of the ADR edited |
| `Consumed-By:` | removes a discovery note | path of the ADR it informed |
| `Completes:` | removes a plan whose work is done | path of the plan |
| `Abandons:` | removes a plan whose work will not be done | path of the plan |
| `Reconciles:` | revises a durable downstream to match the changed decision | path of that downstream |
| `Confirms:` | examines a durable downstream and finds it still correct | path of that downstream |
| `Defers:` | defers reconciling a durable downstream artefact, blocked on named other work | path of that downstream artefact; carries its named blocking condition |

Values are repository-relative paths, in the trailer block at the end of the message, one per line in `Key: value` form — never in prose, which `git interpret-trailers` cannot see. **`Derives-From` sits on the first commit of the artefact's branch, whatever that commit contains**, and names direct upstreams only: a skill produced by a plan step names the plan, not the ADR behind it. Before the first commit, ask what this artefact was produced from and write the path down; `land` refuses a branch whose first commit lacks it, unless the branch is a decision or its first commit carries `Clarifies`, which `land` sends direct to trunk with no human pull request. **The body carries the reason**: a `Revises`, `Clarifies`, `Abandons` or deleting commit says what changed and why, in sentences.

The last three are **verdict** trailers (ADR 0011), recorded by the reviser on a `Revises` branch — one per durable in-tree downstream of the revised ADR, naming that downstream from the revision's side. `land` refuses such a branch while any durable, in-tree downstream (from `history downstream`, filtered to the tree) carries none; see Rule 15. `begin` surfaces the same list as an advisory worklist that blocks nothing.

### Rule 13 — Merging is not mandatory, and nothing of anyone else's is yours to tidy

An experiment may remain unmerged; its branch and worktree stay. Do not remove a branch or a `.worktrees/` directory you did not create, and do not treat an unmerged branch as an error. Cleanup happens on merge, and the script does it.

## What the script decides — do not re-derive it by hand

The trunk (from three refs, never from configuration or prose); whether to isolate and where; the branch name from the artefact path; what a worktree receives; whether a remote exists and which host it names; that a pull request is titled with the first commit's subject; that integration is a two-parent merge and never a squash, rebase or fast-forward; that a decision is landed by a human; what a stop leaves behind; and cleanup. `references/RULES.md` has each rule with its reasoning, for when you need to explain the script's behaviour, not to reproduce it.

## Do not

- Do not create or modify a file before `begin` has run. This is the rule actually broken in practice, and markdown is where it breaks.
- Do not read the trunk, the branch name or the integration path out of `CONTRIBUTING.md`, a README or git configuration, and do not override what `begin` printed with a repository's local convention.
- Do not merge locally, push to the trunk, fast-forward, squash or rebase when `land` stopped. A remote exists, so the fallback does not apply; relay the report.
- Do not describe an artefact as landed, approved or accepted when `land` exited 1 or 3.
- Do not run `git add -A` or `git commit -a` in a checkout whose dirty state is not yours, and do not stash a checkout to get it clean; that is what the worktree is for.
- Do not copy `.venv/`, `node_modules/` or any other built dependency into a worktree or commit one; the script copies only the small configuration files, and copies them rather than moving them.
- Do not write a relationship between artefacts as a sentence and call it recorded. It goes in a trailer.
- Do not define "artefact" here, adjust an artefact's boundary to suit the branching, or specify what a commit contains.
- Do not remove somebody else's branch or worktree.

## When you may deviate

- **Read-only exploration.** This skill does not apply. Reading, searching and running tests that change no file need no branch.
- **Work already proceeding on an artefact branch this workflow created.** You are past `begin`; carry on, and do not run it again mid-artefact.
- **Bookkeeping.** Rule 4's exception, on Rule 4's terms only.
- **A path outside any git repository.** Nothing here applies; say so rather than running `git init` to make it apply.
- **The user explicitly says to work on trunk, or not to branch.** Follow the instruction, and note the deviation in your reply so it is visible rather than silent.

Deviating because the workflow feels heavy for the change in hand is not on this list. A one-line change takes a short-lived branch like anything else.
