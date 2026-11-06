#!/usr/bin/env bash
# git-workflow — the mechanical half of the git-workflow skill.
#
# Usage:
#   bash git-workflow.sh check
#   bash git-workflow.sh begin <artefact-path> [--slug <slug>]
#   bash git-workflow.sh land
#   bash git-workflow.sh --help
#
# Subcommands
#   check   Derive and print the facts the workflow acts on, changing
#           nothing: trunk=<ref>, remote=<name|none>,
#           host=<none|github|unknown:<url>>, contention=<in-place|worktree>.
#   begin   Name the artefact branch from its path; where a remote
#           exists, fetch it and fast-forward the local trunk to the
#           remote's, or stop (exit 1) creating nothing; then branch in
#           place or into .worktrees/<branch> from the trunk, copy the small
#           configuration files into a worktree, and print trunk=, branch=
#           and dir=, and include=.gitignore when the .worktrees/ ignore
#           line was added and awaits the artefact's first commit. Makes no
#           commit. Never stages, stashes, reverts or deletes anything in
#           the primary checkout.
#   land    From the artefact's checkout: refuse unless the first commit
#           since the fork point carries Derives-From or a Clarifies edit
#           to an existing ADR; hand a decision (a new file under docs/adr/,
#           or a Revises trailer) to a human via the host's pull request;
#           print every outstanding deferral now due, and refuse when this
#           branch's own trigger is what makes one due unless it also
#           carries a discharge verdict; otherwise merge with two parents,
#           locally where there is no remote and through hosts/<name>.sh
#           otherwise, bringing the local trunk current after a host merge
#           or noting why not; then clean up, leaving the primary checkout
#           where it was, or on the trunk where the work was in place.
#
# Host modules live in hosts/<name>.sh beside this script. Each is an
# executable taking one of:
#   propose <branch> <trunk>
#                       open a pull request for the pushed branch onto the
#                       trunk, or rewrite the open one's title and
#                       description; its title is the first commit's
#                       subject, and it carries every commit's message and
#                       body
#   merge <branch>      merge it with a merge commit, never squash or rebase
#   settings            print whether the host allows squash and rebase merges
#
# Exit codes
#   0  done: the facts were printed, the branch was begun, or the artefact
#      merged and was cleaned up
#   1  stopped with a report: begin could not fetch or fast-forward the
#      local trunk, and created no branch; or land's host command was
#      missing, failed or refused, the branch is pushed and everything else
#      is left as it was
#   2  usage or a precondition failed: nothing was changed
#   3  stopped by design: the branch is a decision; it is pushed and
#      proposed, and a human merges it
#
# Depends on git, and on the host's command-line tool where a host is
# involved, and on nothing else.

set -u

usage() {
  sed -n '2,/^# Depends/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  local code="$1"; shift
  printf 'git-workflow: %s\n' "$*" >&2
  exit "$code"
}

# check — derive the facts the workflow acts on; change nothing.
#
# Prints four lines to stdout:
#   trunk=<ref>        the first of: a local dev branch, a local develop
#                      branch, the branch refs/remotes/origin/HEAD names
#   remote=<name|none> none when `git remote` prints nothing; origin when
#                      present; otherwise the sole remote
#   host=<...>         none when there is no remote; github when the
#                      remote's URL names github.com in https or ssh
#                      form; otherwise unknown:<url>
#   contention=<...>   in-place when HEAD is the trunk and the working
#                      tree is clean; worktree otherwise
# Exits 2, printing which refs were looked for, when no rung of the
# trunk ladder resolves; exits 2 naming the candidates when there is
# more than one remote and none is origin. Reads configuration keys and
# prose from nowhere: a workflow.trunk key or a CONTRIBUTING.md changes
# nothing.
derive_trunk() {
  if git rev-parse --verify --quiet refs/heads/dev >/dev/null; then echo dev; return 0; fi
  if git rev-parse --verify --quiet refs/heads/develop >/dev/null; then echo develop; return 0; fi
  local head
  if head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    echo "${head#origin/}"; return 0
  fi
  return 1
}

derive_remote() {
  local remotes
  remotes="$(git remote)"
  [ -z "$remotes" ] && { echo none; return 0; }
  if printf '%s\n' "$remotes" | grep -qx origin; then echo origin; return 0; fi
  if [ "$(printf '%s\n' "$remotes" | wc -l | tr -d ' ')" = "1" ]; then echo "$remotes"; return 0; fi
  return 1
}

derive_host() {
  local remote="$1" url
  [ "$remote" = none ] && { echo none; return 0; }
  url="$(git config --get "remote.$remote.url")"   # the configured URL names the host; url.*.insteadOf rewrites are transport
  case "$url" in
    https://github.com/*|http://github.com/*|git@github.com:*|ssh://git@github.com/*|github.com:*) echo github ;;
    *) echo "unknown:$url" ;;
  esac
}

derive_contention() {
  local trunk="$1"
  if [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$trunk" ] && [ -z "$(git status --porcelain)" ]; then
    echo in-place
  else
    echo worktree
  fi
}

cmd_check() {
  git rev-parse --git-dir >/dev/null 2>&1 || die 2 "not inside a git repository"
  local trunk remote host
  trunk="$(derive_trunk)" || die 2 "no trunk resolves: looked for refs/heads/dev, refs/heads/develop and the branch named by refs/remotes/origin/HEAD; this repository is not set up for the workflow (git remote set-head origin -a satisfies it where a remote exists)"
  remote="$(derive_remote)" || die 2 "more than one remote and none named origin: $(git remote | tr '\n' ' ')— say which by naming it origin"
  host="$(derive_host "$remote")"
  printf 'trunk=%s\nremote=%s\nhost=%s\ncontention=%s\n' "$trunk" "$remote" "$host" "$(derive_contention "$trunk")"
}
# begin <artefact-path> [--slug <slug>] — start the artefact's branch.
#
# Names the branch from the path: docs/adr/NNNN-slug.md -> adr-NNNN-slug,
# plans/NNNN-slug.md -> plan-NNNN-slug, docs/discovery/NNNN-slug.md ->
# discovery-NNNN-slug, skills/<name>/SKILL.md -> skill-<name>; any other
# path is ungoverned work and needs --slug, giving chore-<slug>. The file
# need not exist yet.
#
# Runs check. Where a remote exists, first brings the local trunk current
# with sync_trunk: fetches the remote and fast-forwards the local trunk to
# the remote's, so the branch starts from the remote's tip. When it
# cannot (the fetch fails, the local trunk has commits the remote lacks,
# the primary checkout is on the trunk with tracked changes, or the trunk
# is checked out in another worktree), exits 1 with sync_trunk's report
# and creates no branch and no worktree. Then, when contention is
# in-place, creates the branch from the trunk in the primary checkout and
# switches to it. Otherwise creates
# .worktrees/<branch> from the trunk, copies the untracked files under
# .claude/, .env and .mcp.json into it where they exist and never .venv/
# or node_modules/, and, when the repository ignores no .worktrees/,
# appends that line to the worktree's .gitignore and leaves it
# uncommitted: it is bookkeeping and rides on the artefact's first
# commit, which carries the trailer. Makes no commit. Never stages,
# stashes, reverts or deletes anything in the primary checkout.
#
# Prints trunk=<ref>, branch=<name> and dir=<absolute path to work in>,
# then include=.gitignore when it added the ignore line, naming the file
# the artefact's first commit must include.
# When the artefact path is an ADR that already exists on the trunk (a
# revision of it, not a new ADR), additionally prints the ADR's downstream:
# worklist under a worklist: header, one indented path per line, after the
# trunk=/branch=/dir=/include= lines, so the reviser sees the scope up
# front (ADR 0011). It is advisory: it blocks nothing, is skipped silently
# when the history skill's script is absent (not a regular file; its mode
# is never consulted, since it is run with bash and an installed plugin
# does not keep the executable bit), and never changes begin's exit code.
# Exits 2 when the branch already exists, when the path is ungoverned and
# --slug is missing, or when check would; exits 1 when the local trunk
# cannot be brought current.
branch_name_for() {
  # $1 artefact path, $2 optional slug for ungoverned work
  local path="$1" slug="${2:-}" base
  base="$(basename "$path")"
  case "$path" in
    docs/adr/[0-9][0-9][0-9][0-9]-*.md)       echo "adr-${base%.md}" ;;
    plans/[0-9][0-9][0-9][0-9]-*.md)          echo "plan-${base%.md}" ;;
    docs/discovery/[0-9][0-9][0-9][0-9]-*.md) echo "discovery-${base%.md}" ;;
    skills/*/SKILL.md)                        local d="${path#skills/}"; echo "skill-${d%%/*}" ;;
    *)
      [ -n "$slug" ] || return 1
      echo "chore-$slug" ;;
  esac
}

copy_if_present() {
  # copy small configuration from the base checkout into the worktree; never move.
  # Copies only files git does not track (tracked ones are already checked
  # out), each to the same relative path, never overwriting a file present
  # in the worktree; so a tracked directory is filled in, not nested.
  local root="$1" wt="$2" f
  git -C "$root" ls-files -z --others -- .claude .env .mcp.json | while IFS= read -r -d '' f; do
    [ -e "$wt/$f" ] && continue
    mkdir -p "$wt/$(dirname "$f")" && cp -pP "$root/$f" "$wt/$f"
  done
  return 0
}

# begin_worklist PATH TRUNK — print the advisory downstream worklist.
#
# Only when PATH is an ADR already on the trunk (a revision, not a new ADR):
# resolve the sibling history script and print its downstream: section under
# a worklist: header, one indented path per line. Advisory — skips silently
# when PATH is not an on-trunk ADR or the history script is absent, and never
# changes begin's exit code. Invoked at both of cmd_begin's exit points.
begin_worklist() {
  local path="$1" trunk="$2"
  case "$path" in docs/adr/*.md) ;; *) return 0 ;; esac
  git cat-file -e "$trunk:$path" 2>/dev/null || return 0
  local hist; hist="$(script_dir)/../../history/scripts/history.sh"
  [ -f "$hist" ] || return 0
  printf 'worklist:\n'
  bash "$hist" downstream "$path" | awk '/^downstream:$/{f=1;next} /^revises:$/{f=0} f && $0!=""{print "  " $0}'
  return 0
}

cmd_begin() {
  local path="" slug=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --slug) slug="${2:-}"; shift 2 ;;
      -*) die 2 "unknown option $1" ;;
      *) [ -z "$path" ] || die 2 "one artefact path only"; path="$1"; shift ;;
    esac
  done
  [ -n "$path" ] || die 2 "usage: begin <artefact-path> [--slug <slug>]"
  local branch
  branch="$(branch_name_for "$path" "$slug")" || die 2 "$path is governed by no skill: name the branch with --slug <slug> (becomes chore-<slug>)"
  local facts trunk contention root
  facts="$(cmd_check)" || exit $?
  trunk="${facts#*trunk=}"; trunk="${trunk%%
*}"
  contention="${facts#*contention=}"; contention="${contention%%
*}"
  root="$(git rev-parse --show-toplevel)"
  git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null && die 2 "branch $branch already exists"
  local remote msg
  remote="${facts#*remote=}"; remote="${remote%%
*}"
  if [ "$remote" != none ]; then
    msg="$(sync_trunk "$(primary_checkout)" "$remote" "$trunk")" || die 1 "$msg; no branch created"
  fi
  if [ "$contention" = in-place ]; then
    git switch -q -c "$branch" "$trunk" || die 2 "could not create $branch"
    printf 'trunk=%s\nbranch=%s\ndir=%s\n' "$trunk" "$branch" "$root"
    begin_worklist "$path" "$trunk"
    return 0
  fi
  local wt="$root/.worktrees/$branch"
  git worktree add -q "$wt" -b "$branch" "$trunk" || die 2 "could not create worktree $wt"
  copy_if_present "$root" "$wt"
  local include=""
  if ! git -C "$wt" check-ignore -q .worktrees/probe; then   # a path under it: a bare .worktrees matches no directory pattern
    printf '.worktrees/\n' >> "$wt/.gitignore"
    include=.gitignore
  fi
  printf 'trunk=%s\nbranch=%s\ndir=%s\n' "$trunk" "$branch" "$wt"
  [ -z "$include" ] || printf 'include=%s\n' "$include"
  begin_worklist "$path" "$trunk"
}
# land — integrate the artefact branch, or stop and say why.
#
# Run from inside the artefact's checkout, primary or worktree. In order:
#   1. Refuses (exit 2) when HEAD is the trunk, tracked files have
#      uncommitted changes (untracked files are not the artefact and may
#      be a worktree's installed dependencies), or there is nothing since
#      the fork point.
#   2. Decides whether the branch is a decision: a commit since the fork
#      point carries Revises, or the diff against the trunk adds a file
#      under docs/adr/. A decision roots or revises the artefact graph, so
#      it needs no Derives-From. Every other artefact derives from an
#      upstream, so its first commit since the fork point must carry a
#      Derives-From trailer; landing refuses (exit 2) when a non-decision
#      does not. A Clarifies edit to an existing ADR is the exception: not
#      a decision, but needing no Derives-From either, since it adds a
#      self-edge from the ADR to itself rather than deriving from an
#      upstream (ADR 0004). Any Derives-From or Clarifies that is present
#      must be repository-relative (not starting with / or ./), or landing
#      refuses (exit 2).
#   2a. The blast-radius auto-defer (ADR 0011), run inside the same
#      Revises guard as 2b and strictly before it, immediately after the
#      hoisted verdict-pool computation (reconciles_confirms, verdicts).
#      Iterates the same sort -u set of distinct Revises values 2b
#      computes, calling history downstream <value> and filtering to
#      in-tree with the same git cat-file -e "HEAD:$d" test 2b uses — the
#      identical blast radius, not a second computation of it. For each
#      in-tree downstream d of a given value, skip it (no auto-defer)
#      when d is already in the verdict pool (an explicit
#      Reconciles:/Confirms:/Defers: the reviser recorded, which this
#      step never overwrites), when it is already slated for auto-defer
#      against an earlier value in this same pass (a d named by two
#      revised ADRs' downstream sets is cited against the first value in
#      sort order once, never duplicated), or when d is the target of an
#      outstanding deferral (history outstanding-deferrals) whose origin
#      is in this branch's full trigger pool — the same
#      Reconciles/Revises/Derives-From values over trunk..HEAD that 2c
#      computes, not only this branch's Revises values. That d is
#      already owed a discharge by this branch's own trigger pool — the
#      discharge-due check (2c) and the reviser own it, not a fresh
#      auto-defer: an auto-defer Defers: there would re-cite the same
#      origin, which 2c rejects as an invalid re-defer (condition
#      unchanged). Collect one Defers: d value until a plan derives from
#      it trailer per remaining d — the fixed condition text, echoing
#      ADR 0011's own wording ("marks the untouched remainder Deferred
#      until a plan derives from this ADR"); satisfied, per ADR
#      0010/0012, by a later Derives-From: value on trunk. When any were
#      collected, make one git commit -q --allow-empty
#      --cleanup=whitespace titled "Auto-defer the untouched blast
#      radius", body naming each revised ADR covered, carrying one
#      Defers: trailer per auto-deferred d, then recompute
#      reconciles_confirms and verdicts with the same two git log reads
#      the hoisted computation already runs, so both 2b and 2c see the
#      new trailers through the one existing code path, with no second
#      one added. The auto-defer commit carries only Defers: trailers,
#      never Reconciles/Revises/Derives-From, so 2c's branch-local
#      trigger pool is unaffected by the commit itself; every other
#      auto-deferred item becomes a new outstanding deferral, picked up
#      later, unmodified, by history outstanding-deferrals and 2c when
#      something eventually reconciles its origin. Skipped outright when
#      $revises is empty — non-Revises branches are unaffected.
#   2b. The verdict-completeness gate (ADR 0011) — a backstop that
#      rarely fires, since 2a now fills every untouched in-tree
#      downstream's verdict first, rather than the primary action. Still
#      run before anything is pushed so an incomplete revision never
#      reaches the host. When a Revises trailer is present on
#      trunk..HEAD (a revision; new-ADR decisions do not trigger it),
#      consume history downstream <revised-ADR> for each distinct
#      Revises value, filter its downstream: section to paths still in
#      HEAD's tree (git cat-file -e), and read the
#      Reconciles/Confirms/Defers verdict trailers on trunk..HEAD
#      (for Defers, the leading path token only — this pool now includes
#      2a's own auto Defers: trailers). Refuse (exit 2) naming each
#      in-tree downstream carrying no verdict — in practice, only the one
#      case 2a's Remainder exclusion leaves standing: a downstream
#      already owed a discharge by this branch's own Revises (2a excludes
#      it rather than auto-deferring it). The gate consumes the sibling
#      history skill's script (../../history/scripts/history.sh from
#      script_dir) and refuses (exit 2) naming the resolved path when it
#      is not a regular file — a hard stop, so an incomplete revision
#      cannot slip through on a missing dependency. Its mode is never
#      consulted: the script is run with bash, and an installed plugin
#      (tessl plugin pack) does not keep the executable bit. Presence is
#      checked, never the truth of the claim. A decision is then pushed and
#      proposed through the host module, then exit 3 with a report naming
#      the pull request and, one "  artefact: <url>" line each, a link to
#      every ADR the decision adds or revises as it stands on the branch
#      (the host module's link verb), so the human can read it before
#      merging: a human merges it. With no remote a decision
#      cannot be proposed: exit 3, branch left in place.
#   2c. The discharge-due check (ADR 0012), run immediately after 2b and
#      still before anything is pushed. The history-script-executable
#      hard stop and the Reconciles/Confirms/Defers verdict pool computed
#      in 2b are hoisted out of the Revises guard and run unconditionally
#      on every land, since this check needs them whether or not the
#      branch revises an ADR; the 0011 downstream-walk itself stays
#      guarded by Revises, now reading the hoisted pool rather than
#      recomputing it. Then: consume history outstanding-deferrals once,
#      and echo every record it reports due: true under a due-deferrals:
#      header (D:/origin:/condition: per record) — advisory, never
#      changes the exit code. Separately, read this branch's own
#      trunk..HEAD trigger pool (Reconciles/Revises/Derives-From
#      valueonly; unlike the verdict reads, no token-stripping, since
#      these trailers carry only a path). A record is this branch's to
#      discharge only when its origin matches (grep -qxF) a value in that
#      pool AND the query reports it due: false — a pool match already
#      due: true (satisfied by something other than this branch) gets
#      visibility only, never the hard-stop: ADR 0012 rejects a global
#      hard-stop. No in-tree filter runs here (unlike 2b's
#      git cat-file -e): outstanding-ness already scopes the set, a
#      deferred artefact is not a completed one, and an escape verdict
#      needs no file to exist. For each triggered record (D, origin O1),
#      discharge needs one of: Reconciles: D or Confirms: D present in
#      the hoisted verdict pool (presence only, same convention as 2b);
#      or a fresh Defers: D O2 <condition> whose O2 differs from O1
#      (string compare) and is currently unmet — no commit anywhere on
#      trunk (a full scan, not trunk..HEAD) carries a
#      Reconciles/Revises/Derives-From trailer valued O2, and O2 is not
#      itself in this branch's own trigger pool. Refuse (exit 2) naming
#      every triggered D lacking a valid escape: a D with no verdict at
#      all under "this branch triggers a due deferral with no discharge
#      verdict for:", and a D whose only verdict is a Defers: failing
#      either check under "this branch triggers a due deferral with an
#      invalid re-defer (condition unchanged or already met) for:".
#   3. Otherwise, by host. none: from the primary checkout with the trunk
#      checked out (switching to it first when the work was in place),
#      git merge --no-ff. A host module: push, propose, then merge, both
#      from the primary checkout; afterwards, whether or not the primary
#      checkout is on the trunk, bring the local trunk current with
#      sync_trunk (fast-forwarded in place where the primary is on it, or
#      moved by ref where it is not), and read the merge commit from the
#      remote for the landed line. When it cannot, print a note and carry
#      on: a local trunk with commits the remote lacks, a trunk checked out
#      in another worktree, or a primary on the trunk with tracked changes
#      and behind the remote, gets the note and no fast-forward. The host
#      module only merges — it never deletes a
#      branch, so it cannot trip over the artefact's worktree; all
#      teardown belongs to step 4. unknown host: push, exit 1. A missing
#      host command, or one that fails or refuses: push if not yet
#      pushed, exit 1 with a report giving the pull request if one was
#      opened, the command, the state left behind and the permission hint
#      Bash(gh pr merge *). Before a host merge, the module's settings are
#      read and a squash or rebase allowance is reported, not changed.
#   4. On a merge only, and owned entirely by this script rather than the
#      host: from the primary checkout (chdir there first, so removing a
#      worktree never pulls the running process's own directory away),
#      remove the worktree (--force, because it holds the untracked config
#      files begin copied in), delete the local branch, delete the remote
#      branch where a remote exists. The primary checkout is left where it
#      was: a parked primary stays on its branch. Where the work was in
#      place the checkout was switched to the trunk in 3. With no remote,
#      where the primary checkout is on neither the trunk nor the branch,
#      no merge can run there: exit 1 with a report.
# sync_trunk PRIMARY REMOTE TRUNK — bring the local trunk current.
#
# Fetches REMOTE and fast-forwards the local TRUNK to REMOTE/TRUNK,
# whatever PRIMARY's HEAD. Every git command runs as git -C PRIMARY with
# git's own stderr suppressed. The local TRUNK must be an ancestor of
# REMOTE/TRUNK, so a trunk with commits the remote lacks never reaches a
# merge; equal, it returns 0 untouched. Behind, where PRIMARY's HEAD is
# TRUNK, its tracked files must be clean and it is fast-forwarded with
# merge --ff-only; where it is not, the ref is moved with a fetch into
# refs/heads/TRUNK, which git refuses where TRUNK is checked out in
# another worktree. Never switches PRIMARY.
#
# Prints nothing on success. On failure prints one line and returns 1:
#   could not fetch REMOTE
#   could not fast-forward TRUNK to REMOTE/TRUNK: local TRUNK has commits
#     REMOTE/TRUNK lacks; push them if they belong on the trunk, or reset
#     TRUNK to REMOTE/TRUNK if they do not        (ancestry check failed)
#   could not fast-forward TRUNK to REMOTE/TRUNK  (any other failure)
sync_trunk() {
  local primary="$1" remote="$2" trunk="$3"
  local ff="could not fast-forward $trunk to $remote/$trunk"
  git -C "$primary" fetch -q "$remote" >/dev/null 2>&1 || { printf 'could not fetch %s\n' "$remote"; return 1; }
  git -C "$primary" merge-base --is-ancestor "$trunk" "$remote/$trunk" >/dev/null 2>&1 || {
    printf '%s: local %s has commits %s/%s lacks; push them if they belong on the trunk, or reset %s to %s/%s if they do not\n' \
      "$ff" "$trunk" "$remote" "$trunk" "$trunk" "$remote" "$trunk"
    return 1; }
  [ "$(git -C "$primary" rev-parse "$trunk" 2>/dev/null)" = "$(git -C "$primary" rev-parse "$remote/$trunk" 2>/dev/null)" ] && return 0
  if [ "$(git -C "$primary" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$trunk" ]; then
    # the primary is on the trunk: fast-forward its checkout, never over its tracked changes
    [ -z "$(git -C "$primary" status --porcelain --untracked-files=no 2>/dev/null)" ] || { printf '%s\n' "$ff"; return 1; }
    git -C "$primary" merge -q --ff-only "$remote/$trunk" >/dev/null 2>&1 || { printf '%s\n' "$ff"; return 1; }
  else
    # parked elsewhere: move the ref; git refuses where the trunk is checked out in another worktree
    git -C "$primary" fetch -q "$remote" "refs/heads/$trunk:refs/heads/$trunk" >/dev/null 2>&1 || { printf '%s\n' "$ff"; return 1; }
  fi
  return 0
}

# primary_checkout — the physical path of the repository's primary checkout.
primary_checkout() { physical "$(git worktree list --porcelain | awk 'NR==1 && $1=="worktree"{print $2}')"; }

script_dir() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P; }
physical() { (cd "$1" 2>/dev/null && pwd -P); }

# stop CODE SUMMARY URL COMMAND BRANCH REMOTE PRIMARY WT [LINKS] — report and
# exit. LINKS, optional, is newline-separated URLs, each printed after the
# pull request as "  artefact: <url>".
stop() {
  local code="$1" summary="$2" url="$3" command="$4" branch="$5" remote="$6" primary="$7" wt="$8" links="${9:-}"
  printf 'git-workflow: stopped: %s\n' "$summary"
  [ -n "$url" ] && printf '  pull request: %s\n' "$url"
  [ -n "$links" ] && printf '%s\n' "$links" | sed '/^$/d; s/^/  artefact: /'
  [ -n "$command" ] && printf '  command: %s\n' "$command"
  local pushed="not pushed"
  if [ "$remote" != none ] && git ls-remote --exit-code --heads "$remote" "$branch" >/dev/null 2>&1; then pushed="pushed to $remote at $(git rev-parse --short "$branch")"; fi
  printf '  state: branch %s %s; %s; primary checkout on %s; nothing merged, nothing cleaned up.\n' \
    "$branch" "$pushed" "$([ -n "$wt" ] && echo "worktree $wt kept" || echo "no worktree")" "$(git -C "$primary" rev-parse --abbrev-ref HEAD)"
  if [ "$code" = 3 ]; then
    printf '  this branch is a decision: a human merges it.\n'
  else
    printf '  to let future artefacts land unattended, allow the merge command in the harness permission settings, for example Bash(gh pr merge *).\n'
  fi
  exit "$code"
}

cleanup_after_merge() {
  local primary="$1" wt="$2" branch="$3" remote="${5:-none}"
  # chdir into the primary checkout first: removing $wt must not pull the
  # running process's own working directory out from under it, which is what
  # happens when land was invoked from inside the worktree it is removing.
  cd "$primary" || return 0
  if [ -n "$wt" ]; then git worktree remove --force "$wt" || printf 'git-workflow: note: could not remove worktree %s\n' "$wt"; fi
  git branch -d "$branch" >/dev/null 2>&1 || git branch -D "$branch" >/dev/null 2>&1 || true
  # The host module merges only; deleting the remote branch is ours, so gh
  # never has to touch — and trip over — the artefact's worktree.
  if [ "$remote" != none ]; then
    git push -q "$remote" --delete "$branch" >/dev/null 2>&1 || printf 'git-workflow: note: could not delete the remote branch %s on %s\n' "$branch" "$remote"
  fi
  return 0
}

cmd_land() {
  git rev-parse --git-dir >/dev/null 2>&1 || die 2 "not inside a git repository"
  local trunk remote host branch
  trunk="$(derive_trunk)" || die 2 "no trunk resolves: looked for refs/heads/dev, refs/heads/develop and the branch named by refs/remotes/origin/HEAD"
  remote="$(derive_remote)" || die 2 "more than one remote and none named origin: $(git remote | tr '\n' ' ')"
  host="$(derive_host "$remote")"
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [ "$branch" != "$trunk" ] || die 2 "HEAD is the trunk ($trunk): land runs from the artefact branch"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die 2 "working tree is dirty: tracked files have uncommitted changes; commit or discard before landing"
  local first
  first="$(git rev-list --reverse "$trunk..HEAD" | head -1)"
  [ -n "$first" ] || die 2 "nothing to land: no commits since the fork point from $trunk"
  local decision=0
  [ -n "$(git log --format='%(trailers:key=Revises,valueonly)' "$trunk..HEAD" | sed '/^$/d')" ] && decision=1
  git diff --name-status "$trunk...HEAD" | grep -qE '^A[[:space:]]+docs/adr/' && decision=1

  # A decision roots or revises the artefact graph and needs no
  # Derives-From; a Clarifies edit to an existing ADR adds a self-edge
  # and needs none either; every other artefact derives from an upstream,
  # so its first commit must carry one. A Derives-From or Clarifies that
  # is present is validated as repository-relative either way.
  local trailer clarifies
  trailer="$(git log -1 --format='%(trailers:key=Derives-From,valueonly)' "$first" | sed '/^$/d')"
  clarifies="$(git log -1 --format='%(trailers:key=Clarifies,valueonly)' "$first" | sed '/^$/d')"
  if [ -n "$clarifies" ]; then
    printf '%s\n' "$clarifies" | grep -qE '^(\./|/)' && die 2 "Clarifies must be a repository-relative path, got: $clarifies"
  fi
  if [ -z "$trailer" ]; then
    { [ "$decision" -eq 1 ] || [ -n "$clarifies" ]; } || die 2 "the first commit since the fork point ($(git rev-parse --short "$first")) carries no Derives-From trailer"
  else
    printf '%s\n' "$trailer" | grep -qE '^(\./|/)' && die 2 "Derives-From must be a repository-relative path, got: $trailer"
  fi

  # The verdict-completeness gate (ADR 0011). A Revises branch revises an
  # accepted ADR; every durable, in-tree downstream of that ADR must carry
  # a verdict. Runs here, before the push, so an incomplete revision never
  # reaches the host. New-ADR decisions have no downstream to reconcile and
  # must not trigger it, so the gate is guarded by Revises being present.
  local revises
  revises="$(git log --format='%(trailers:key=Revises,valueonly)' "$trunk..HEAD" | sed '/^$/d')"

  # Hoisted unconditional prerequisites (ADR 0012 mechanism 2): the
  # discharge-due check below needs both the history script and the
  # verdict pool whether or not this branch revises an ADR, so they run
  # here, outside the revises guard. The ADR 0011 downstream-walk itself
  # stays guarded below, reading this same pool rather than recomputing it.
  local hist; hist="$(script_dir)/../../history/scripts/history.sh"
  [ -f "$hist" ] || die 2 "the revision gate needs the history skill's script; it is not a regular file at $hist"
  # The verdict set: Reconciles/Confirms/Defers values on trunk..HEAD. For
  # Defers, the leading whitespace-delimited token (the downstream path)
  # only; the remainder is the opaque blocking condition. reconciles_confirms
  # is the Reconciles/Confirms-only subset the discharge-due check needs,
  # since (unlike this gate) it never accepts a Defers escape by presence
  # alone.
  local reconciles_confirms verdicts
  reconciles_confirms="$(
    git log --format='%(trailers:key=Reconciles,valueonly)' "$trunk..HEAD" | sed '/^$/d'
    git log --format='%(trailers:key=Confirms,valueonly)'   "$trunk..HEAD" | sed '/^$/d'
  )"
  verdicts="$(
    printf '%s\n' "$reconciles_confirms"
    git log --format='%(trailers:key=Defers,valueonly)' "$trunk..HEAD" | sed '/^$/d' | awk '{print $1}'
  )"

  if [ -n "$revises" ]; then
    # The blast-radius auto-defer (ADR 0011, land doc-comment 2a), run
    # strictly before the verdict-completeness gate below (2b). Reuses
    # the same sort -u Revises set and the same git cat-file -e in-tree
    # filter 2b uses below, so it walks the identical blast radius, not a
    # second computation of it.
    local autodefer_pool outstanding_autodefer value d slated="" defer_trailers=""
    autodefer_pool="$(
      git log --format='%(trailers:key=Reconciles,valueonly)'   "$trunk..HEAD" | sed '/^$/d'
      git log --format='%(trailers:key=Revises,valueonly)'      "$trunk..HEAD" | sed '/^$/d'
      git log --format='%(trailers:key=Derives-From,valueonly)' "$trunk..HEAD" | sed '/^$/d'
    )"
    # D<TAB>origin pairs for every outstanding deferral, due or not: 2a's
    # exclusion cares only whether the origin is in this branch's pool.
    outstanding_autodefer="$(bash "$hist" outstanding-deferrals | awk '
      /^D: / { d=substr($0,4); next }
      /^origin: / { print d "\t" substr($0,9) }
    ')"
    while IFS= read -r value; do
      [ -n "$value" ] || continue
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        git cat-file -e "HEAD:$d" 2>/dev/null || continue           # keep durable in-tree downstreams only
        printf '%s\n' "$verdicts" | grep -qxF "$d" && continue      # an explicit verdict: never overwritten
        printf '%s\n' "$slated"   | grep -qxF "$d" && continue      # already slated against an earlier value this pass
        local od_origin=""
        od_origin="$(printf '%s\n' "$outstanding_autodefer" | awk -F'\t' -v want="$d" '$1 == want { print $2; exit }')"
        if [ -n "$od_origin" ] && printf '%s\n' "$autodefer_pool" | grep -qxF "$od_origin"; then
          continue   # already owed a discharge by this branch's own trigger pool: 2c and the reviser own it
        fi
        slated="$slated$d
"
        defer_trailers="${defer_trailers}Defers: $d $value until a plan derives from it
"
      done < <(bash "$hist" downstream "$value" | awk '/^downstream:$/{f=1;next} /^revises:$/{f=0} f{print}')
    done < <(printf '%s\n' "$revises" | sort -u)
    if [ -n "$defer_trailers" ]; then
      local covers
      covers="$(printf '%s\n' "$revises" | sort -u | paste -sd, - | sed 's/,/, /g')"
      git commit -q --allow-empty --cleanup=whitespace -m "$(printf 'Auto-defer the untouched blast radius\n\nCovers the untouched remainder of: %s\n\n%s' "$covers" "$defer_trailers")" \
        || die 1 "could not make the auto-defer commit"
      # Re-read exactly as the hoisted computation above does, so both 2b
      # and 2c see the new trailers through the one existing code path.
      reconciles_confirms="$(
        git log --format='%(trailers:key=Reconciles,valueonly)' "$trunk..HEAD" | sed '/^$/d'
        git log --format='%(trailers:key=Confirms,valueonly)'   "$trunk..HEAD" | sed '/^$/d'
      )"
      verdicts="$(
        printf '%s\n' "$reconciles_confirms"
        git log --format='%(trailers:key=Defers,valueonly)' "$trunk..HEAD" | sed '/^$/d' | awk '{print $1}'
      )"
    fi

    local missing="" value d
    while IFS= read -r value; do
      [ -n "$value" ] || continue
      # Only the downstream: section: the lines strictly between the
      # downstream: and revises: headers history prints.
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        git cat-file -e "HEAD:$d" 2>/dev/null || continue           # keep durable in-tree downstreams only
        printf '%s\n' "$verdicts" | grep -qxF "$d" && continue      # a verdict names it: presence, not truth
        missing="$missing$d
"
      done < <(bash "$hist" downstream "$value" | awk '/^downstream:$/{f=1;next} /^revises:$/{f=0} f{print}')
    done < <(printf '%s\n' "$revises" | sort -u)
    if [ -n "$missing" ]; then
      die 2 "$(printf 'this revision does not account for every durable downstream; no verdict (Reconciles/Confirms/Defers) names:\n%s' "$(printf '%s' "$missing" | sort -u)")"
    fi
  fi

  # The discharge-due check (ADR 0012). Consumes history
  # outstanding-deferrals once; its output backs both the visibility list
  # and the hard-stop. Advisory visibility first, never changing the exit
  # code; the hard-stop, below, can.
  local outstanding
  outstanding="$(bash "$hist" outstanding-deferrals)"
  printf 'due-deferrals:\n'
  printf '%s\n' "$outstanding" | awk '
    /^D: / { d=substr($0,4); next }
    /^origin: / { o=substr($0,9); next }
    /^condition: / { c=substr($0,12); next }
    /^due: / {
      due=substr($0,6)
      if (due == "true") printf "D: %s\norigin: %s\ncondition: %s\n\n", d, o, c
      next
    }
  '

  # The branch-local trigger pool: Reconciles/Revises/Derives-From
  # valueonly over trunk..HEAD, no token-stripping (unlike the verdict
  # reads above, these trailers carry only a path).
  local trigger_pool
  trigger_pool="$(
    git log --format='%(trailers:key=Reconciles,valueonly)'   "$trunk..HEAD" | sed '/^$/d'
    git log --format='%(trailers:key=Revises,valueonly)'      "$trunk..HEAD" | sed '/^$/d'
    git log --format='%(trailers:key=Derives-From,valueonly)' "$trunk..HEAD" | sed '/^$/d'
  )"
  # The same three trailer kinds, scanned over the whole of trunk's own
  # history (not trunk..HEAD): what a re-defer's new origin must be absent
  # from to count as currently unmet.
  local trunk_pool
  trunk_pool="$(
    git log --format='%(trailers:key=Reconciles,valueonly)'   "$trunk" | sed '/^$/d'
    git log --format='%(trailers:key=Revises,valueonly)'      "$trunk" | sed '/^$/d'
    git log --format='%(trailers:key=Derives-From,valueonly)' "$trunk" | sed '/^$/d'
  )"

  # D/origin/due triples for every outstanding deferral, tab-separated.
  local records
  records="$(printf '%s\n' "$outstanding" | awk '
    BEGIN { d=""; o=""; due="" }
    /^D: / { if (d != "") print d "\t" o "\t" due; d=substr($0,4); o=""; due=""; next }
    /^origin: / { o=substr($0,9); next }
    /^due: / { due=substr($0,6); next }
    END { if (d != "") print d "\t" o "\t" due }
  ')"

  local no_verdict="" bad_redefer="" d o due
  while IFS=$'\t' read -r d o due; do
    [ -n "$d" ] || continue
    printf '%s\n' "$trigger_pool" | grep -qxF "$o" || continue   # not this branch's to discharge
    [ "$due" = false ] || continue                               # already due: visibility only
    printf '%s\n' "$reconciles_confirms" | grep -qxF "$d" && continue   # Reconciles: D or Confirms: D, presence only
    # The leading token (D) of a Defers trailer, matched against the
    # verdict pool's convention, then its full value re-read so O2 — the
    # second whitespace token — can be parsed.
    local defer_full=""
    defer_full="$(
      git log --format='%(trailers:key=Defers,valueonly)' "$trunk..HEAD" | sed '/^$/d' | awk -v want="$d" '
        { line=$0; if (match(line, /^[^ \t]+/) && substr(line, RSTART, RLENGTH) == want) { print line; exit } }
      '
    )"
    if [ -n "$defer_full" ]; then
      local o2=""
      o2="$(printf '%s\n' "$defer_full" | awk '
        { line=$0; sub(/^[^ \t]+[ \t]+/, "", line); if (match(line, /^[^ \t]+/)) print substr(line, RSTART, RLENGTH) }
      ')"
      if [ -n "$o2" ] && [ "$o2" != "$o" ]; then
        local met=0
        printf '%s\n' "$trunk_pool"   | grep -qxF "$o2" && met=1
        printf '%s\n' "$trigger_pool" | grep -qxF "$o2" && met=1
        [ "$met" -eq 0 ] && continue   # a fresh, differing, currently-unmet re-defer: valid
      fi
      bad_redefer="$bad_redefer$d
"
    else
      no_verdict="$no_verdict$d
"
    fi
  done <<< "$records"

  if [ -n "$no_verdict" ] || [ -n "$bad_redefer" ]; then
    local msg=""
    [ -n "$no_verdict" ] && msg="${msg}this branch triggers a due deferral with no discharge verdict for:
$(printf '%s' "$no_verdict" | sort -u)
"
    [ -n "$bad_redefer" ] && msg="${msg}this branch triggers a due deferral with an invalid re-defer (condition unchanged or already met) for:
$(printf '%s' "$bad_redefer" | sort -u)
"
    die 2 "$msg"
  fi

  local primary here inplace=0 wt=""
  primary="$(primary_checkout)"
  here="$(physical "$(git rev-parse --show-toplevel)")"
  if [ "$here" = "$primary" ]; then inplace=1; else wt="$here"; fi

  local module="" url=""
  case "$host" in github) module="$(script_dir)/hosts/$host.sh" ;; esac

  # A remote means the pull-request path: push first, whatever follows.
  if [ "$remote" != none ]; then
    git push -q -u "$remote" "$branch" 2>/dev/null || stop 1 "could not push $branch to $remote" "" "git push -u $remote $branch" "$branch" "$remote" "$primary" "$wt"
  fi

  if [ "$decision" -eq 1 ]; then
    [ "$remote" != none ] || stop 3 "this branch is a decision and there is no remote to propose it on" "" "" "$branch" "$remote" "$primary" "$wt"
    [ -n "$module" ] || stop 1 "no host module for $host: the branch is pushed; propose it by hand" "" "" "$branch" "$remote" "$primary" "$wt"
    url="$(bash "$module" propose "$branch" "$trunk")" || {
      rc=$?; [ "$rc" = 127 ] && stop 1 "gh is not on PATH; the pull request could not be opened" "" "gh pr create" "$branch" "$remote" "$primary" "$wt"
      stop 1 "the host refused to open the pull request" "" "gh pr create" "$branch" "$remote" "$primary" "$wt"; }
    # Link every ADR the decision adds or revises, as it stands on the branch.
    local adr links=""
    for adr in $( { git diff --name-status "$trunk...HEAD" | awk '$1=="A" && $2 ~ /^docs\/adr\// {print $2}'
                    git log --format='%(trailers:key=Revises,valueonly)' "$trunk..HEAD"; } | sed '/^$/d' | sort -u); do
      links="$links$(bash "$module" link "$url" "$branch" "$adr" 2>/dev/null)"$'\n'
    done
    stop 3 "decision proposed; a human merges it" "$url" "" "$branch" "$remote" "$primary" "$wt" "$links"
  fi

  if [ "$host" = none ]; then
    if [ "$inplace" -eq 1 ]; then
      git switch -q "$trunk" || die 2 "could not switch the primary checkout to $trunk"
    else
      [ "$(git -C "$primary" rev-parse --abbrev-ref HEAD)" = "$trunk" ] || stop 1 "the primary checkout is on $(git -C "$primary" rev-parse --abbrev-ref HEAD), not the trunk $trunk, so the local merge cannot run there" "" "" "$branch" "$remote" "$primary" "$wt"
    fi
    git -C "$primary" merge -q --no-ff -m "Merge $branch" "$branch" || die 1 "merge of $branch into $trunk failed; resolve it in the primary checkout"
    cleanup_after_merge "$primary" "$wt" "$branch" "$trunk" "$remote"
    printf 'landed %s into %s as %s\n' "$branch" "$trunk" "$(git -C "$primary" rev-parse --short "$trunk")"
    return 0
  fi

  [ -n "$module" ] || stop 1 "no host module for $host: the branch is pushed; open and merge the pull request by hand" "" "" "$branch" "$remote" "$primary" "$wt"

  local settings
  if settings="$(bash "$module" settings 2>/dev/null)"; then
    case "$settings" in *squash=true*|*rebase=true*) printf 'git-workflow: warning: the host allows what the workflow forbids (%s); disable squash and rebase merges at the repository level\n' "$settings" ;; esac
  fi
  url="$(bash "$module" propose "$branch" "$trunk")" || {
    rc=$?; [ "$rc" = 127 ] && stop 1 "gh is not on PATH; the pull request could not be opened" "" "gh pr create" "$branch" "$remote" "$primary" "$wt"
    stop 1 "the host refused to open the pull request" "" "gh pr create" "$branch" "$remote" "$primary" "$wt"; }
  if [ "$inplace" -eq 1 ]; then git switch -q "$trunk" || die 2 "could not switch the primary checkout to $trunk"; fi
  (cd "$primary" && bash "$module" merge "$branch" "$trunk") || {
    rc=$?; [ "$rc" = 127 ] && stop 1 "gh is not on PATH; the pull request is open and unmerged" "$url" "gh pr merge $branch --merge --delete-branch" "$branch" "$remote" "$primary" "$wt"
    stop 1 "the merge was refused; the pull request is open and unmerged" "$url" "gh pr merge $branch --merge --delete-branch" "$branch" "$remote" "$primary" "$wt"; }
  # The merge commit is the remote trunk's tip, read before anything else can move it.
  local merged msg
  merged="$(git -C "$primary" ls-remote "$remote" "refs/heads/$trunk" 2>/dev/null | awk 'NR==1{print substr($1,1,7)}')"
  msg="$(sync_trunk "$primary" "$remote" "$trunk")" || printf 'git-workflow: note: %s\n' "$msg"
  cleanup_after_merge "$primary" "$wt" "$branch" "$trunk" "$remote"
  if [ -n "$merged" ]; then
    printf 'landed %s into %s via %s as %s\n' "$branch" "$trunk" "$host" "$merged"
  else
    printf 'landed %s into %s via %s\n' "$branch" "$trunk" "$host"
  fi
}

main() {
  case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    check) shift; cmd_check "$@" ;;
    begin) shift; cmd_begin "$@" ;;
    land)  shift; cmd_land "$@" ;;
    "") usage >&2; exit 2 ;;
    *) printf 'git-workflow: unknown subcommand %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
}

main "$@"
