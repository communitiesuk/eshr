---
name: setup
description: Checks a repository against myelin's requirements manifest and applies consented, admin-gated fixes to the misconfigurations it flags. TRIGGER when asked to check or verify myelin's setup or requirements, to run a "doctor"/"setup" pass on a repository, or to fix a flagged host or merge-settings misconfiguration. SKIP for the automatic SessionStart check — the non-interactive tripwire that runs the same check in `--hook` mode; this skill is its manual, interactive counterpart.
---

# Setup

This is myelin's manual check-and-fix path. It verifies a repository
against the requirements manifest (`skills/setup/manifest.json`, the
single source of truth — see `docs/adr/0013-requirements-declared-and-verified.md`)
and, where the user asks, applies the consented, admin-gated fixes the
manifest carries.

A distributed `SessionStart` hook runs the same check in `--hook` mode on
every session start: quiet when healthy, advisory, never blocking. That
is the automatic tripwire and it fixes nothing. This skill is its manual
counterpart — run on demand, interactive, and the only path that changes
anything. Invoke it when asked to check or verify the setup, to run a
"doctor"/"setup" pass, or to put right a flagged misconfiguration.

The harness states this skill's base directory when it loads the skill.
Call that `$SKILL_DIR`.

## 1. Re-run the check and report it

Run the check script in its default full-report mode and report what it
prints — every REQUIRED and DESIRABLE item as a pass or a fail, each
failure with its fix, and the reported opt-in line:

```sh
bash "$SKILL_DIR/scripts/check.sh"
```

The script is read-only: it inspects, it never changes anything. Report
its output as the finding. Do not answer from the README or from memory;
the manifest the script reads is authoritative.

## 2. Offer fixes — consent-gated, admin-gated, never silent

A fix is a change to the user's repository or host. Apply one **only**
with the user's explicit consent **and only** where it is safe to apply,
and **never** silently (`docs/adr/0013-requirements-declared-and-verified.md`).
Offer; do not act until the user agrees.

**The DESIRABLE merge-settings fix.** When the merge-settings check
fails, the host allows squash or rebase merges against myelin's
merge-commits-only opinion. The manifest's fix is the `gh api -X PATCH`
that disables those buttons. Applying it needs host admin, so:

1. Confirm admin. Run, for the repository's remote:

   ```sh
   gh api repos/{owner}/{repo} --jq .permissions.admin
   ```

   Apply the fix only if this is `true`. If it is `false`, or the call
   cannot answer, do **not** attempt the PATCH: report that the fix needs
   host admin the user does not hold, and leave it to a repository owner.

2. With admin confirmed and the user's explicit consent, run the fix
   inline, the way the `release` skill runs `gh` — the exact command the
   manifest carries:

   ```sh
   gh api -X PATCH repos/{owner}/{repo} -F allow_squash_merge=false -F allow_rebase_merge=false
   ```

   No separate fix script ships; the command is run from here,
   consent-gated. Re-run the check afterwards to confirm it passed.

**REQUIRED failures.** Report each with the fix the check printed — a
command where the item carries one (the trunk item's
`git remote set-head origin -a`), otherwise its install guidance (the
host CLI). A local fix may be run with the user's explicit consent;
installing software is the user's to do. Never apply one silently.

## 3. The `gh pr merge` opt-in — report, never set

The `gh pr merge` opt-in is a user decision, not a pass/fail check. The
check prints it; relay it to the user verbatim, including the exact line:

```
Bash(gh pr merge *)
```

with the manifest's note that it goes in `.claude/settings.json` (checked
in) or `.claude/settings.local.json` (per clone). **Never** write that
line into a settings file yourself and never treat the opt-in as a fix to
apply — letting the agent land its own work is the user's choice to make.

## Do not

- Do not apply any fix silently. Every change to the repository or host
  is offered first and applied only on the user's explicit consent.
- Do not run the merge-settings PATCH without confirming
  `.permissions.admin` is `true`. No admin, no PATCH.
- Do not set the `gh pr merge` opt-in. Report its line; leave the
  decision to the user.
- Do not re-implement the checks or hand-maintain the requirement list.
  The manifest is the single source of truth; the check script reads it.
- Do not duplicate the automatic hook's job. The `SessionStart` hook is
  the quiet tripwire; this skill is the on-demand, interactive path.
