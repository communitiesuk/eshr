# Rules the git-workflow script enforces, and why

The skill body says when to run `scripts/git-workflow.sh` and what only a
model can decide. These are the rules the script carries out. They are
kept here for the reasoning, not for execution: do not run these
commands by hand where the script runs them for you. Rationale in
`docs/adr/0003-git-workflow.md` and `docs/adr/0004-where-does-history-live.md`.

## Rule 5 — Isolate on contention, not by default

Branch in the primary checkout when that checkout is **on trunk and clean**. Otherwise branch together with a worktree at `.worktrees/<branch>` inside the repository. Both conditions are readable without judgement, and **nothing has to be inferred about whether work is "parallel"** — run the commands and read the answer off them.

```sh
git rev-parse --abbrev-ref HEAD   # must equal the trunk derived by Rule 6, not merely a default-looking branch
git status --porcelain            # must print nothing
git worktree add .worktrees/<branch> -b <branch> <trunk>   # if either check fails
```

When you isolate, work inside `.worktrees/<branch>` and do not touch the primary checkout's files at all: its dirty state belongs to somebody else's work in progress. Never `git add -A` there, never stash it, never revert or delete a file to make it clean.

**`.worktrees/` must be gitignored.** Where the repository's `.gitignore` lacks the entry, add it *inside the new worktree* and leave it uncommitted: it goes into the artefact's first commit, so it rides on the artefact's branch under Rule 4 and the first commit still carries the trailer. Not in the primary checkout, which would put it on trunk, and not in a commit of its own, which records nothing.

## Rule 6 — Fork point is derived, never configured

The trunk to branch from is the first of these that exists. All three are refs that resolve; **there is no fourth rung**:

1. a local `dev` branch,
2. a local `develop` branch,
3. the branch named by `refs/remotes/origin/HEAD`.

```sh
git rev-parse --verify --quiet refs/heads/dev
git rev-parse --verify --quiet refs/heads/develop
git symbolic-ref --quiet --short refs/remotes/origin/HEAD
```

**A repository in which none of the three resolves is not set up for this workflow, and the workflow stops rather than guessing.** Say what is missing and what would fix it — `git remote set-head origin -a` sets `origin/HEAD` in one command for any repository with a remote — and do not proceed on an assumption about which branch is the trunk. This is a precondition on the repository, not a branching model: a wrong fork point is the one error here that is invisible when it is made, since a branch cut from the wrong trunk looks correct until it is merged. The removed fourth rung named "the repository's existing default branch" without saying how to find it, and git records that only in `init.defaultBranch`, which is configuration — so any implementation had to invent a hardcoded branch list under a heading that says derived and never configured.

Never from configuration — not `init.defaultBranch`, not a `workflow.trunk`-style key, not any other value — and never from prose in a `CONTRIBUTING.md`, a README or a house style guide. A repository that carries a local `dev` gets `dev` even where every document in it says `main`. The same holds for branch naming and for the integration path: derive them, do not look them up.

Where a remote exists, the branch starts from a local trunk just fast-forwarded to the remote's, which is not integration and so not Rule 10's merge.

## Rule 7 — Naming

- `<artefact-type>-NNNN-slug` where the artefact carries a number, so the branch shares the artefact's identifier: `adr-0003-git-workflow`, `plan-0003-git-workflow`.
- `<type>-<slug>` where there is no number: `skill-git-workflow`, `chore-gitignore-worktrees`.

The type token is the artefact noun from Rule 2's table — `adr`, `plan`, `discovery`, `skill`, or `code` for a `test-first-workflow` code change — or `chore` for work governed by no skill. Take the number and slug from the artefact file itself, so the two agree: an ADR written as `docs/adr/0003-git-workflow.md` is produced on `adr-0003-git-workflow` and on nothing else. A repository's local convention does not override this; `feature/*`, initials, dates and bare slugs are all wrong here, however confidently a contributing guide asserts them.

## Rule 8 — Worktree bootstrap is split

A new worktree receives tracked files only. Ignored files are not in the object database, so git cannot populate them.

- **Small configuration files** — `.claude/`, `.env`, `.mcp.json` — are **copied** from the base checkout into the new worktree. Copy, never move: the base checkout still needs them. Without this you lose the permissions in `.claude/settings.local.json`.
- **Built dependencies** — `.venv/`, `node_modules/` — are **not** copied. Provisioning them needs per-repository knowledge and stays with the governing skill.
- **Anything neither list names**: copy it if it is small, machine-local configuration that would otherwise be lost; leave it if it is generated, large or platform-specific.

Do not stage a worktree wholesale after bootstrapping: `.gitignore` may not cover what you copied in (`venv/` and `.venv/` are not the same pattern) and `git add -A` then commits a build directory into the artefact. `post-checkout` is the native seam for repository-specific bootstrap — repositories may use it, this workflow does not require it.

## Rule 10 — Integration preserves structure

> A branch lands as a **merge commit with two parents**, into the branch it forked from. Never squashed. Never fast-forwarded.

The no-fast-forward merge is what brackets the commits belonging to one artefact. A squash discards the individual commits and their trailers with them, and destroys the red/green sequence `test-first-workflow` and `skill-forge` mandate. A fast-forward keeps the commits but loses the record of which artefact they belonged to.

```sh
git merge --no-ff <branch>
```

Run it from a checkout that has the trunk checked out — normally the primary checkout, since trunk cannot be checked out in two worktrees at once, so you cannot merge into it from the artefact's own worktree. A dirty primary checkout does not block the merge as long as the merge touches different paths, which is the usual case; it is not a reason to disturb the files already sitting there.

## Rule 11 — A pull request is the default; a local merge is the fallback

Propose and land **through the host's pull-request mechanism whenever the repository has a remote whose host provides one**. The local merge is the **fallback**, used when there is no such remote — not an equal alternative chosen by preference. Check with `git remote`: no output means no remote, which means the fallback. Like the fork point, this is derived and never read from configuration or a contributing guide, so a repository with no remote takes the local merge even where its documentation instructs a pull request. Do not invent an `origin`, and do not leave the artefact unlanded in a repository with no remote because a pull request was impossible there; both are failures to land. A refused merge where a remote exists is a different case, below.

**The host is an implementation detail this skill does not know.** The commands for a particular host belong to a **platform skill, which does not yet exist**; until it does, `git-workflow` implements the fallback path only. Where a remote exists, use whatever host tooling the session already provides and hold it to Rule 10's outcome: state the merge action explicitly rather than accepting a default (at least one major host squashes by default), and disable squash and rebase merges at the repository level wherever the host allows it, so the prohibition is enforced rather than merely written down.

**A pull request is titled with the first commit's subject**, and its description is every commit's message and body, oldest first; landing again rewrites both.

**A refused merge ends the procedure at step 7.** When the pull request is open and its merge is refused — by the host, or by the harness's permission layer — stop and report: the pull request URL, the exact command that was refused, and the state left behind (branch pushed, worktree kept, primary checkout not returned to trunk, because Rule 14 runs on merge and nothing merged). Say that allowing the merge command in the harness's permission settings, for example `Bash(gh pr merge *)`, lets future artefacts land unattended. Do **not** take the local-merge fallback: it exists for a repository with no remote, and here it would bypass whoever refused. Do not describe the artefact as landed.

**No host tooling is not the no-remote case.** The fallback is selected by one fact, `git remote` printing nothing, and by nothing else. Where a remote exists but the session has no command that can open a pull request — no `gh`, no host API, or one that fails for want of credentials — push the branch, then stop and report exactly as for a refusal, naming the command that was missing or failed. The pushed branch is what the human opens the pull request from; a local merge into trunk is not a substitute for it, and neither is cleaning up as if something had merged.

**A pull request buys enforcement, and only that.** The platform can refuse a squash and refuse a direct push to trunk. It buys **no review**: an agent that opens a pull request and immediately merges it has been reviewed by nobody. Do not describe such a merge as approved, accepted or signed off. **A decision is landed by a human.** If the branch adds a file under `docs/adr/` or any of its commits carries a `Revises` trailer, push, open the pull request, stop and report, exactly as for a refused merge; do not merge it. Every other artefact the agent lands itself.

## Rule 14 — Cleanup on merge

```sh
git worktree remove .worktrees/<branch>   # --force once dependencies are installed
git branch -d <branch>
```

`--force` is required where dependencies were installed, because removal refuses on untracked files. The now-empty `.worktrees/` parent may stay. Work done **in the primary checkout returns that checkout to trunk**, or the next artefact branches from the previous one. Where the work was isolated the primary checkout never moved: **confirm its branch, do not check it out** — `git rev-parse --abbrev-ref HEAD` answers the question, while `git checkout <trunk>` against a checkout already on trunk changes nothing and writes a spurious line into the reflog. With the primary checkout left off the trunk, the local trunk is advanced by ref and never by switching the primary. After cleanup, `git branch` shows no artefact branch, `git worktree list` shows only the primary checkout, and HEAD is where it was, or on trunk where the work was in place.

## Rule 15 — The verdict-completeness gate at land

A `Revises` branch revises an accepted ADR, and a revision must account for everything downstream of it (ADR 0011). So `land` gates such a branch: it lands only when **every durable, in-tree downstream of the revised ADR carries a verdict**. The downstream set is `history downstream <revised-ADR>` (ADR 0010's query, which the gate consumes — a repository without the history skill's script cannot run the gate), filtered to the paths still in the branch tip's tree: a completed plan has left the tree and needs no verdict. A verdict is one of the Rule 9 verdict trailers — `Reconciles:`, `Confirms:` or `Defers:` — on the branch, naming that downstream. For `Defers:`, only the leading path is read; the named blocking condition after it is opaque to the gate.

The gate checks **presence, not truth**: that at least one verdict names each downstream, never whether the verdict's claim is correct (that is the ADR 0008 reviewer's fidelity check). Recording *exactly one* verdict per downstream is ADR 0011's norm, not something the gate enforces. The refusal happens before the branch is pushed, so an incomplete revision never reaches the host, and it names each downstream still without a verdict. A new-ADR decision has no downstream to reconcile and does not trigger the gate. `begin` surfaces the same `downstream:` list as an advisory worklist that blocks nothing.
