# land: refuse, hand a decision to a human, merge locally where there is no
# remote or through the host module otherwise, stop and report when the
# host cannot, and clean up only after a merge.
#
# Coverage of the eval scenarios' FAILS IF conditions (criteria.json):
#   git-workflow-0 #1 dev or main moved: the agent merged a decision -> "decision: with no remote it cannot be proposed, exit 3, branch kept"
#   git-workflow-0 #2 branch kept, numbered name                      -> the same decision test; begin.sh naming tests
#   git-workflow-0 #3 in-place branching, worktree removed            -> begin.sh worktree tests; decision tests keep the worktree
#   git-workflow-0 #4 primary files staged/stashed/reverted            -> begin.sh "on the trunk but dirty" test
#   git-workflow-0 #5 fork point                                       -> begin.sh fork-point test
#   git-workflow-0 #6 config not copied / nested, deps carried         -> begin.sh bootstrap tests
#   git-workflow-0 #7 .worktrees/ line uncommitted / on trunk          -> begin.sh bookkeeping tests; "the first worktree artefact ... lands"
#   git-workflow-0 #8 trailer missing / not repo-relative / later      -> the trailer refusals
#   git-workflow-0 #9 a remote invented                                -> the no-remote tests: "git remote still empty"
#   git-workflow-1 #1 trunk moved locally or on origin                 -> decision and stop tests
#   git-workflow-1 #2 branch deleted after no merge                    -> stop tests assert the branch exists
#   git-workflow-1 #3 never pushed / origin behind                     -> "pushed at the same SHA" assertions
#   git-workflow-1 #5 worktree removed, HEAD moved, without a merge    -> stop tests

R="$TMP_ROOT/land"
mkdir -p "$R/bin" && cp "$(dirname "$SCRIPT")/tests/stub-gh.sh" "$R/bin/gh" && chmod +x "$R/bin/gh"
export GH_STUB_LOG="$R/gh.log"; export PATH="$R/bin:$PATH"
land() { local d="$1"; shift; (cd "$d" && bash "$SCRIPT" land "$@" 2>&1); }
land_rc() { local d="$1"; shift; (cd "$d" && bash "$SCRIPT" land "$@" >/dev/null 2>&1); echo $?; }
parents() { (cd "$1" && git log -1 --format=%P "$2" | wc -w | tr -d ' '); }
bare_tip() { git --git-dir="$1/.origin/repo.git" rev-parse "$2" 2>/dev/null; }

# Build a repository with an artefact branch carrying one committed ADR.
#   artefact DIR [fixture options...] then: --where in-place|worktree
#   The trailer is written unless NOTRAILER=1; the artefact is docs/discovery/0002-x.md
#   (a note, so that landing it is not a decision)
#   unless ADRPATH is set; extra commits via EXTRA=1. With CLARIFIES=1 the
#   first commit carries a Clarifies trailer (value CLARIFIESVAL, default
#   ADRPATH) instead of Derives-From.
artefact() {
  local dir="$1"; shift
  local where=worktree opts=()
  while [ $# -gt 0 ]; do case "$1" in --where) where="$2"; shift 2 ;; *) opts+=("$1"); shift ;; esac; done
  fixture "$dir" --trunk dev "${opts[@]}" >/dev/null || return 2
  (cd "$dir" && printf '.worktrees/\n' >> .gitignore && g add .gitignore && g commit -q -m "ignore worktrees" && { git remote | grep -q . && g push -q origin dev || true; })
  if [ "$where" = worktree ]; then (cd "$dir" && g switch -q -c topic && printf 'x\n' > t.txt && g add t.txt && g commit -q -m topic); fi
  local out; out="$(cd "$dir" && bash "$SCRIPT" begin "${ADRPATH:-docs/discovery/0002-x.md}" 2>&1)" || { echo "$out"; return 2; }
  local wd; wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  ( cd "$wd" && mkdir -p "$(dirname "${ADRPATH:-docs/discovery/0002-x.md}")" && printf -- '---\ntitle: x\n---\n' > "${ADRPATH:-docs/discovery/0002-x.md}" && g add -A \
    && if [ "${NOTRAILER:-0}" = 1 ]; then g commit -q -m "Add ADR"; \
       elif [ "${CLARIFIES:-0}" = 1 ]; then g commit -q -m "$(printf 'Add ADR\n\nClarifies: %s\n' "${CLARIFIESVAL:-${ADRPATH:-docs/discovery/0002-x.md}}")"; \
       else g commit -q -m "$(printf 'Add ADR\n\nDerives-From: %s\n' "${TRAILER:-docs/discovery/0001-note.md}")"; fi )
  if [ "${EXTRA:-0}" = 1 ]; then ( cd "$wd" && printf 'more\n' >> "${ADRPATH:-docs/discovery/0002-x.md}" && g add -A && g commit -q -m "Extend ADR" ); fi
  echo "$wd"
}
# github-flavoured remote: origin's URL names github.com so host=github, and a
# url.insteadOf rewrite in the repository's config sends every fetch and push
# to the bare repository instead, so git and the stub host share one origin.
githubify() { (cd "$1" && git remote set-url origin https://github.com/example/repo.git && git config "url.$(pwd)/.origin/repo.git.insteadOf" https://github.com/example/repo.git); export GH_STUB_BARE="$1/.origin/repo.git" GH_STUB_TRUNK=dev; }

t "no remote: the first worktree artefact in a repository lands when its first commit includes begin's ignore line"
  fixture "$R/f1" --trunk dev --dirty >/dev/null
  out="$(cd "$R/f1" && bash "$SCRIPT" begin plans/0002-x.md 2>&1)"
  wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  assert_contains "$out" "include=.gitignore"
  (cd "$wd" && mkdir -p plans && printf -- '---\ntitle: x\n---\n' > plans/0002-x.md && g add plans/0002-x.md .gitignore \
    && g commit -q -m "$(printf 'Add plan\n\nDerives-From: docs/adr/0001-one.md\n')")
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  assert_eq "2" "$(parents "$R/f1" dev)" "dev must end in a two-parent merge: $out"
  assert_eq "1" "$(cd "$R/f1" && git show dev:.gitignore | grep -c '^\.worktrees/$')" "the ignore line must reach dev through the merge"
  [ -d "$wd" ] && fail "worktree left behind: $out"
  true

t "refusal: on the trunk"
  fixture "$R/r1" --trunk dev >/dev/null
  out="$(land "$R/r1"; echo "exit=$?")"; assert_contains "$out" "exit=2"; assert_contains "$out" "trunk"

t "refusal: dirty working tree"
  wd="$(artefact "$R/r2" --where in-place)"; (cd "$wd" && printf 'dirt\n' >> README.md)
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=2"; assert_contains "$out" "dirty"
  assert_eq "discovery-0002-x" "$(cd "$R/r2" && git rev-parse --abbrev-ref HEAD)" "refusal must change nothing"

t "refusal: nothing since the fork point"
  fixture "$R/r3" --trunk dev --branch empty >/dev/null; (cd "$R/r3" && g switch -q empty && g reset -q --hard dev)
  out="$(land "$R/r3"; echo "exit=$?")"; assert_contains "$out" "exit=2"; assert_contains "$out" "nothing"

t "refusal: first commit has no Derives-From trailer"
  wd="$(NOTRAILER=1 artefact "$R/r4" --where in-place)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=2"; assert_contains "$out" "Derives-From"
  assert_eq "$(cd "$R/r4" && git rev-parse dev)" "$(cd "$R/r4" && git rev-parse dev)" ; assert_eq "1" "$(cd "$R/r4" && git rev-list --count dev..discovery-0002-x)"

t "refusal: trailer only on a later commit"
  wd="$(NOTRAILER=1 EXTRA=0 artefact "$R/r5" --where in-place)"
  (cd "$wd" && printf 'more\n' >> docs/discovery/0002-x.md && g add -A && g commit -q -m "$(printf 'Extend\n\nDerives-From: docs/discovery/0001-note.md\n')")
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=2"; assert_contains "$out" "first commit"

t "refusal: trailer value not repository-relative"
  wd="$(TRAILER=./docs/discovery/0001-note.md artefact "$R/r6" --where in-place)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=2"; assert_contains "$out" "relative"
  wd="$(TRAILER=/docs/discovery/0001-note.md artefact "$R/r7" --where in-place)"
  assert_eq "2" "$(land_rc "$wd")"

t "decision: a new docs/adr file is proposed, never merged, exit 3"
  wd="$(ADRPATH=docs/adr/0002-x.md artefact "$R/d1" --remote origin --where worktree)"; githubify "$R/d1"; : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"; assert_contains "$out" "pull/7"; assert_contains "$out" "human"
  assert_eq "$(cd "$R/d1" && git rev-parse adr-0002-x)" "$(bare_tip "$R/d1" adr-0002-x)" "branch must be pushed at the same SHA"
  assert_contains "$(cat "$GH_STUB_LOG")" "pr create"
  assert_contains "$(grep 'pr create' "$GH_STUB_LOG")" "--title Add ADR"
  case "$(grep 'pr create' "$GH_STUB_LOG")" in *--fill*) fail "the pull request was filled by gh, not titled" ;; esac
  case "$(cat "$GH_STUB_LOG")" in *"pr merge"*) fail "merge was attempted on a decision" ;; esac
  assert_eq "$(cd "$R/d1" && git rev-parse dev)" "$(bare_tip "$R/d1" dev)" "origin's trunk must equal the local trunk"
  assert_eq "0" "$(cd "$R/d1" && git log --merges --format=%H dev | wc -l | tr -d ' ')" "trunk gained a merge"
  assert_eq "0" "$(cd "$R/d1" && git rev-list --count dev ^"$(git merge-base dev adr-0002-x)")" "trunk moved locally"
  [ -d "$R/d1/.worktrees/adr-0002-x" ] || fail "worktree removed on a decision"

t "decision: a multi-commit branch is titled from its first commit, its description every commit, exit 3"
  wd="$(ADRPATH=docs/adr/0002-x.md EXTRA=1 artefact "$R/d8" --remote origin --where worktree)"; githubify "$R/d8"; : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  assert_contains "$(grep 'pr create' "$GH_STUB_LOG")" "--title Add ADR"
  case "$(grep 'pr create' "$GH_STUB_LOG")" in *"--title Extend ADR"*) fail "titled from the last commit" ;; esac
  assert_contains "$(cat "$GH_STUB_LOG")" "Extend ADR"
  assert_contains "$(cat "$GH_STUB_LOG")" "Derives-From: docs/discovery/0001-note.md"

t "decision: landing again with the pull request open rewrites its title and description from every commit, exit 3"
  wd="$(ADRPATH=docs/adr/0002-x.md artefact "$R/d7" --remote origin --where worktree)"; githubify "$R/d7"
  (cd "$wd" && g commit -q --allow-empty -m "$(printf 'Record review round 1 of docs/adr/0002-x.md\n\nReview record, round 1.\n')")
  : > "$GH_STUB_LOG"
  out="$(GH_STUB_PR=open land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"; assert_contains "$out" "pull/7"
  case "$(cat "$GH_STUB_LOG")" in *"pr create"*) fail "a second pull request was opened" ;; esac
  assert_contains "$(cat "$GH_STUB_LOG")" "pr edit adr-0002-x --title Add ADR --body"
  assert_contains "$(cat "$GH_STUB_LOG")" "Review record, round 1."
  assert_contains "$(cat "$GH_STUB_LOG")" "Derives-From: docs/discovery/0001-note.md"
  assert_eq "$(cd "$R/d7" && git rev-parse adr-0002-x)" "$(bare_tip "$R/d7" adr-0002-x)" "branch must be pushed at the same SHA"

t "decision: a Revises trailer is proposed, never merged, exit 3"
  wd="$(ADRPATH=docs/adr/0001-one.md artefact "$R/d2" --remote origin --where in-place)"
  (cd "$wd" && printf 'changed\n' >> docs/adr/0001-one.md && g add -A && g commit -q -m "$(printf 'Revise\n\nRevises: docs/adr/0001-one.md\n')")
  githubify "$R/d2"; : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=3"
  case "$(cat "$GH_STUB_LOG")" in *"pr merge"*) fail "merge was attempted on a Revises branch" ;; esac
  assert_eq "adr-0001-one" "$(cd "$R/d2" && git rev-parse --abbrev-ref HEAD)" "primary checkout must stay on the branch"

t "decision: with no remote it cannot be proposed, exit 3, branch kept"
  wd="$(ADRPATH=docs/adr/0002-x.md artefact "$R/d3" --where worktree)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=3"
  assert_eq "1" "$(cd "$R/d3" && git for-each-ref refs/heads/adr-0002-x | wc -l | tr -d ' ')"
  assert_eq "0" "$(cd "$R/d3" && git log --merges --format=%H dev | wc -l | tr -d ' ')"

t "decision: the report links the new ADR as it stands on its branch, after the pull request (#96)"
  wd="$(ADRPATH=docs/adr/0002-x.md artefact "$R/l1" --remote origin --where worktree)"; githubify "$R/l1"; : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  assert_contains "$out" "  artefact: https://github.com/example/repo/blob/adr-0002-x/docs/adr/0002-x.md"
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c '^  artefact: ')" "exactly one artefact link: $out"
  assert_eq "artefact" "$(printf '%s\n' "$out" | grep -E '^  (pull request|artefact): ' | sed -n '2s/^  \([a-z]*\).*/\1/p')" "the link must follow the pull request: $out"

t "decision: a Revises branch links the revised ADR once, though it is also the file it edits (#96)"
  wd="$(ADRPATH=docs/adr/0001-one.md artefact "$R/l2" --remote origin --where in-place)"
  (cd "$wd" && printf 'changed\n' >> docs/adr/0001-one.md && g add -A && g commit -q -m "$(printf 'Revise\n\nRevises: docs/adr/0001-one.md\n')")
  githubify "$R/l2"; : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  assert_contains "$out" "  artefact: https://github.com/example/repo/blob/adr-0001-one/docs/adr/0001-one.md"
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c '^  artefact: ')" "the revised ADR must be linked once: $out"

t "decision: with no remote there is no pull request, so no artefact link (#96)"
  wd="$(ADRPATH=docs/adr/0002-x.md artefact "$R/l3" --where worktree)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=3"
  case "$out" in *"artefact:"*) fail "an artefact link was invented with no host: $out" ;; esac

t "not a decision: a merged artefact prints no artefact link (#96)"
  wd="$(artefact "$R/l4" --remote origin --where worktree)"; githubify "$R/l4"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"
  case "$out" in *"artefact:"*) fail "a non-decision printed an artefact link: $out" ;; esac

t "host module: link builds the blob URL from the pull request URL, and refuses anything else (#96)"
  gh_mod="$(dirname "$SCRIPT")/hosts/github.sh"
  assert_eq "https://github.com/o/r/blob/adr-0003-y/docs/adr/0003-y.md" "$(bash "$gh_mod" link https://github.com/o/r/pull/12 adr-0003-y docs/adr/0003-y.md)"
  out="$(bash "$gh_mod" link https://github.com/o/r adr-0003-y docs/adr/0003-y.md; echo "exit=$?")"
  assert_eq "exit=1" "$out" "a non-pull-request URL must print nothing and exit 1"

t "not a decision: editing an existing ADR without Revises merges normally"
  wd="$(ADRPATH=docs/adr/0001-one.md artefact "$R/d4" --where in-place)"
  assert_eq "0" "$(land_rc "$wd")"; assert_eq "2" "$(parents "$R/d4" dev)"

t "Clarifies: a first commit carrying Clarifies and no Derives-From on an existing-ADR edit lands direct to trunk, exit 0, no PR"
  wd="$(CLARIFIES=1 ADRPATH=docs/adr/0001-one.md artefact "$R/c1" --where in-place)"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  assert_eq "2" "$(parents "$R/c1" dev)" "dev must end in a two-parent merge: $out"
  assert_eq "dev" "$(cd "$R/c1" && git rev-parse --abbrev-ref HEAD)" "primary checkout must end on the trunk"
  assert_eq "0" "$(cd "$R/c1" && git for-each-ref refs/heads/adr-0001-one | wc -l | tr -d ' ')" "branch must be gone"

t "refusal: editing an existing ADR with no trailer at all is still refused, exit 2"
  wd="$(NOTRAILER=1 ADRPATH=docs/adr/0001-one.md artefact "$R/c2" --where in-place)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=2"; assert_contains "$out" "Derives-From"
  assert_eq "adr-0001-one" "$(cd "$R/c2" && git rev-parse --abbrev-ref HEAD)" "refusal must change nothing"

t "refusal: Clarifies value not repository-relative"
  wd="$(CLARIFIES=1 ADRPATH=docs/adr/0001-one.md CLARIFIESVAL=./docs/adr/0001-one.md artefact "$R/c3" --where in-place)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=2"; assert_contains "$out" "relative"

t "decision: a new docs/adr file with no Derives-From is proposed, not refused, exit 3"
  wd="$(ADRPATH=docs/adr/0002-x.md NOTRAILER=1 artefact "$R/d5" --remote origin --where worktree)"; githubify "$R/d5"; : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"; assert_contains "$out" "human"
  assert_contains "$(cat "$GH_STUB_LOG")" "pr create"
  case "$(cat "$GH_STUB_LOG")" in *"pr merge"*) fail "merge attempted on a decision" ;; esac
  assert_eq "$(cd "$R/d5" && git rev-parse adr-0002-x)" "$(bare_tip "$R/d5" adr-0002-x)" "branch must be pushed at the same SHA"

t "decision: a Revises branch whose first commit has no Derives-From is proposed, exit 3"
  fixture "$R/d6" --trunk dev --remote origin >/dev/null; githubify "$R/d6"
  out="$(cd "$R/d6" && bash "$SCRIPT" begin docs/adr/0001-one.md 2>&1)"
  wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  (cd "$wd" && printf 'changed\n' >> docs/adr/0001-one.md && g add -A && g commit -q -m "$(printf 'Revise\n\nRevises: docs/adr/0001-one.md\n')")
  : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=3"
  case "$(cat "$GH_STUB_LOG")" in *"pr merge"*) fail "merge attempted on a Revises branch" ;; esac

t "no remote: merge in place, primary ends on the trunk, two parents, branch gone, no remote invented"
  wd="$(artefact "$R/m1" --where in-place)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"
  assert_eq "dev" "$(cd "$R/m1" && git rev-parse --abbrev-ref HEAD)"
  assert_eq "2" "$(parents "$R/m1" dev)"
  assert_eq "0" "$(cd "$R/m1" && git for-each-ref refs/heads/discovery-0002-x | wc -l | tr -d ' ')"
  assert_eq "" "$(cd "$R/m1" && git remote)"; assert_eq "0" "$(cd "$R/m1" && git for-each-ref refs/remotes | wc -l | tr -d ' ')"

t "no remote: merge from a worktree with an untracked .venv, worktree removed, dirt untouched, no checkout line"
  wd="$(artefact "$R/m2" --dirty --where worktree)"
  (cd "$R/m2" && g switch -q dev 2>/dev/null || true)   # primary back on trunk, dirt travels with it
  before="$(cd "$R/m2" && git status --porcelain | sort)"
  reflog_before="$(cd "$R/m2" && grep -c 'checkout: moving from dev' .git/logs/HEAD)"   # the helper's own switch to topic
  mkdir -p "$wd/.venv/bin" && printf 'x\n' > "$wd/.venv/bin/python"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"
  assert_eq "2" "$(parents "$R/m2" dev)"
  [ -d "$R/m2/.worktrees/discovery-0002-x" ] && fail "worktree not removed"
  assert_eq "$before" "$(cd "$R/m2" && git status --porcelain | sort)" "primary dirt must be untouched"
  assert_contains "$(cd "$R/m2" && git status --porcelain)" " M README.md"
  assert_contains "$(cd "$R/m2" && git status --porcelain)" "?? notes.txt"
  assert_eq "$reflog_before" "$(cd "$R/m2" && grep -c 'checkout: moving from dev' .git/logs/HEAD)" "land added a checkout line to the primary reflog"
  assert_eq "0" "$(cd "$R/m2" && git for-each-ref refs/heads/discovery-0002-x | wc -l | tr -d ' ')"

t "no remote: primary checkout on neither trunk nor branch -> exit 1, nothing merged"
  wd="$(artefact "$R/m3" --where worktree)"   # primary is on topic
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=1"; assert_contains "$out" "trunk"
  assert_eq "0" "$(cd "$R/m3" && git log --merges --format=%H dev | wc -l | tr -d ' ')"
  [ -d "$R/m3/.worktrees/discovery-0002-x" ] || fail "worktree removed without a merge"

t "github: merge in place with --merge, local trunk fast-forwarded to origin, cleanup"
  wd="$(artefact "$R/g1" --remote origin --where in-place)"; githubify "$R/g1"; : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"
  merge_line="$(grep 'pr merge' "$GH_STUB_LOG")"; assert_contains "$merge_line" "--merge"
  case "$merge_line" in *--squash*|*--rebase*) fail "squash or rebase passed to the host" ;; esac
  assert_eq "dev" "$(cd "$R/g1" && git rev-parse --abbrev-ref HEAD)"
  assert_eq "$(bare_tip "$R/g1" dev)" "$(cd "$R/g1" && git rev-parse dev)" "local trunk must equal origin's"
  assert_eq "2" "$(parents "$R/g1" dev)"
  assert_eq "0" "$(cd "$R/g1" && git for-each-ref refs/heads/discovery-0002-x | wc -l | tr -d ' ')"

t "github: merge from a worktree, run from the primary checkout, worktree removed"
  wd="$(artefact "$R/g2" --remote origin --where worktree)"; (cd "$R/g2" && g switch -q dev); githubify "$R/g2"; : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"
  [ -d "$R/g2/.worktrees/discovery-0002-x" ] && fail "worktree not removed"
  assert_eq "$(bare_tip "$R/g2" dev)" "$(cd "$R/g2" && git rev-parse dev)"
  assert_eq "dev" "$(cd "$R/g2" && git rev-parse --abbrev-ref HEAD)"

t "github: settings that allow a squash are reported before merging"
  wd="$(artefact "$R/g3" --remote origin --where in-place)"; githubify "$R/g3"
  out="$(GH_STUB_SQUASH=true land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"; assert_contains "$out" "squash"

t "stop: the host refuses the merge -> pushed, branch and worktree kept, HEAD unchanged, exit 1 with the hint"
  wd="$(artefact "$R/s1" --remote origin --where worktree)"; githubify "$R/s1"; : > "$GH_STUB_LOG"
  head_before="$(cd "$R/s1" && git rev-parse --abbrev-ref HEAD)"; origin_before="$(bare_tip "$R/s1" dev)"
  out="$(GH_STUB_MERGE=refuse land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=1"
  assert_contains "$out" "pull/7"; assert_contains "$out" "gh pr merge"; assert_contains "$out" "Bash(gh pr merge *)"
  assert_eq "$(cd "$R/s1" && git rev-parse discovery-0002-x)" "$(bare_tip "$R/s1" discovery-0002-x)" "pushed at the same SHA"
  assert_eq "1" "$(cd "$R/s1" && git for-each-ref refs/heads/discovery-0002-x | wc -l | tr -d ' ')"
  [ -d "$R/s1/.worktrees/discovery-0002-x" ] || fail "worktree removed without a merge"
  assert_eq "$head_before" "$(cd "$R/s1" && git rev-parse --abbrev-ref HEAD)"
  assert_eq "$origin_before" "$(bare_tip "$R/s1" dev)" "origin trunk moved"

t "stop: gh absent from PATH -> pushed, kept, exit 1 naming gh"
  wd="$(artefact "$R/s2" --remote origin --where worktree)"; githubify "$R/s2"
  out="$( (cd "$wd" && PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "^$R/bin$" | tr '\n' ':')" bash "$SCRIPT" land 2>&1); echo "exit=$?")"
  assert_contains "$out" "exit=1"; assert_contains "$out" "gh"
  assert_eq "$(cd "$R/s2" && git rev-parse discovery-0002-x)" "$(bare_tip "$R/s2" discovery-0002-x)" "pushed at the same SHA"
  assert_eq "1" "$(cd "$R/s2" && git for-each-ref refs/heads/discovery-0002-x | wc -l | tr -d ' ')"
  [ -d "$R/s2/.worktrees/discovery-0002-x" ] || fail "worktree removed without a merge"

t "stop: an unknown host -> pushed, kept, exit 1"
  wd="$(artefact "$R/s3" --remote origin --where worktree)"
  (cd "$R/s3" && git remote set-url origin https://gitlab.example.org/x/y.git && git config "url.$(pwd)/.origin/repo.git.insteadOf" https://gitlab.example.org/x/y.git)
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=1"; assert_contains "$out" "gitlab.example.org"
  assert_eq "$(cd "$R/s3" && git rev-parse discovery-0002-x)" "$(bare_tip "$R/s3" discovery-0002-x)" "pushed at the same SHA"
  assert_eq "0" "$(cd "$R/s3" && git log --merges --format=%H dev | wc -l | tr -d ' ')"

t "github: the pull request is opened against the derived trunk"
  wd="$(artefact "$R/g4" --remote origin --where in-place)"; githubify "$R/g4"; : > "$GH_STUB_LOG"
  assert_eq "0" "$(land_rc "$wd")"
  assert_contains "$(grep 'pr create' "$GH_STUB_LOG")" "--base dev"

t "github: a multi-commit non-decision branch is titled from its first commit, its description every commit"
  wd="$(EXTRA=1 artefact "$R/g5" --remote origin --where in-place)"; githubify "$R/g5"; : > "$GH_STUB_LOG"
  assert_eq "0" "$(land_rc "$wd")"
  assert_contains "$(grep 'pr create' "$GH_STUB_LOG")" "--title Add ADR"
  case "$(grep 'pr create' "$GH_STUB_LOG")" in *"--title Extend ADR"*|*--fill*) fail "not titled from the first commit" ;; esac
  assert_contains "$(cat "$GH_STUB_LOG")" "Extend ADR"
  assert_contains "$(cat "$GH_STUB_LOG")" "Derives-From: docs/discovery/0001-note.md"

t "github: land from inside the worktree with untracked files, primary off-trunk -> clean, no gh worktree warning (issue #46)"
  wd="$(artefact "$R/wc1" --remote origin --where worktree)"; githubify "$R/wc1"; : > "$GH_STUB_LOG"
  printf 'x\n' > "$wd/untracked-note.txt"   # a non-ignored untracked file, so a non-force worktree remove would refuse, as begin's copied .claude/ did in the wild
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  case "$out" in *"could not remove worktree"*|*"contains modified"*) fail "gh's non-force worktree cleanup leaked into land's output" ;; esac
  [ -d "$R/wc1/.worktrees/discovery-0002-x" ] && fail "worktree not removed"
  assert_eq "0" "$(cd "$R/wc1" && git for-each-ref refs/heads/discovery-0002-x | wc -l | tr -d ' ')"
  assert_eq "2" "$(git --git-dir="$R/wc1/.origin/repo.git" log -1 --format=%P dev | wc -w | tr -d ' ')" "origin trunk is not a two-parent merge"

t "github: land from inside the worktree with untracked files, primary on trunk but dirty -> clean, dirt untouched (PR #52)"
  wd="$(artefact "$R/wc2" --remote origin --where worktree)"; githubify "$R/wc2"
  (cd "$R/wc2" && git switch -q dev && printf 'dirt\n' >> README.md)   # primary on trunk, dirty
  : > "$GH_STUB_LOG"
  printf 'x\n' > "$wd/untracked-note.txt"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  case "$out" in *"could not remove worktree"*|*"contains modified"*) fail "gh's non-force worktree cleanup leaked into land's output" ;; esac
  [ -d "$R/wc2/.worktrees/discovery-0002-x" ] && fail "worktree not removed"
  assert_eq "dev" "$(cd "$R/wc2" && git rev-parse --abbrev-ref HEAD)"
  assert_contains "$(cd "$R/wc2" && git status --porcelain)" " M README.md"

t "github: land deletes the remote branch itself, not the host module"
  wd="$(artefact "$R/wc3" --remote origin --where in-place)"; githubify "$R/wc3"; : > "$GH_STUB_LOG"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"
  # show-ref, not bare_tip: `git rev-parse <missing-ref>` echoes the name back
  # rather than printing nothing, so it cannot test for absence.
  git --git-dir="$R/wc3/.origin/repo.git" show-ref --verify --quiet refs/heads/discovery-0002-x && fail "remote branch not deleted"

t "github: primary parked off the trunk -> local trunk moved by ref to the merge, primary left where it was"
  wd="$(artefact "$R/k1" --remote origin --where worktree)"; githubify "$R/k1"; : > "$GH_STUB_LOG"
  status_before="$(cd "$R/k1" && git status --porcelain)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"
  assert_eq "topic" "$(cd "$R/k1" && git rev-parse --abbrev-ref HEAD)" "primary checkout must stay where it was"
  assert_contains "$out" "as $(bare_tip "$R/k1" dev | cut -c1-7)" "the landed line must name the merge commit: $out"
  assert_eq "$(bare_tip "$R/k1" dev)" "$(cd "$R/k1" && git rev-parse dev)" "local trunk must equal origin's: $out"
  assert_eq "$status_before" "$(cd "$R/k1" && git status --porcelain)" "the primary's status changed"

t "github: local trunk diverged, primary parked -> note, local trunk unchanged, landed line names the merge"
  wd="$(artefact "$R/k2" --remote origin --where worktree)"
  (cd "$R/k2" && g switch -q dev && printf 'local\n' > LOCAL-ONLY.md && g add LOCAL-ONLY.md && g commit -q -m "local: ahead" && g switch -q topic)
  githubify "$R/k2"; : > "$GH_STUB_LOG"
  dev_before="$(cd "$R/k2" && git rev-parse dev)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"
  assert_eq "topic" "$(cd "$R/k2" && git rev-parse --abbrev-ref HEAD)" "primary checkout must stay where it was"
  assert_contains "$out" "as $(bare_tip "$R/k2" dev | cut -c1-7)" "the landed line must name the merge commit: $out"
  assert_contains "$out" "could not fast-forward" "no note for the diverged trunk: $out"
  assert_eq "$dev_before" "$(cd "$R/k2" && git rev-parse dev)" "the diverged local trunk moved"

t "github: trunk checked out in another worktree, behind -> note, that worktree untouched, landed line names the merge"
  wd="$(artefact "$R/k3" --remote origin --where worktree)"
  (cd "$R/k3" && g worktree add -q "$R/trunk-wt" dev)
  githubify "$R/k3"; : > "$GH_STUB_LOG"
  wt_head_before="$(cd "$R/trunk-wt" && git rev-parse HEAD)"; wt_status_before="$(cd "$R/trunk-wt" && git status --porcelain)"
  out="$(land "$wd"; echo "exit=$?")"; assert_contains "$out" "exit=0"
  assert_eq "topic" "$(cd "$R/k3" && git rev-parse --abbrev-ref HEAD)" "primary checkout must stay where it was"
  assert_contains "$out" "as $(bare_tip "$R/k3" dev | cut -c1-7)" "the landed line must name the merge commit: $out"
  assert_contains "$out" "could not fast-forward" "no note for the trunk checked out elsewhere: $out"
  assert_eq "$wt_head_before" "$(cd "$R/trunk-wt" && git rev-parse HEAD)" "the other worktree's HEAD moved"
  assert_eq "$wt_status_before" "$(cd "$R/trunk-wt" && git status --porcelain)" "the other worktree's status changed"

# --- Step 1: the verdict-completeness gate (ADR 0011, plan 0017) -------------
#
# revision DIR [fixture options...] — build a Revises branch of
# docs/adr/0001-one.md carrying a durable in-tree downstream
# plans/9001-downstream.md (Derives-From: docs/adr/0001-one.md) committed
# first, then the ADR edit committed with Revises: docs/adr/0001-one.md and
# any trailer lines held in $VERDICT. begin is in-place (the fixture is on a
# clean trunk), so wd is the repository root. Echoes wd. history downstream
# docs/adr/0001-one.md therefore returns plans/9001-downstream.md.
revision() {
  local dir="$1"; shift
  fixture "$dir" --trunk dev "$@" >/dev/null || return 2
  local out wd
  out="$(cd "$dir" && bash "$SCRIPT" begin docs/adr/0001-one.md 2>&1)" || { echo "$out"; return 2; }
  wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  ( cd "$wd" \
    && mkdir -p plans && printf -- '---\ntitle: d\n---\n' > plans/9001-downstream.md \
    && g add plans/9001-downstream.md \
    && g commit -q -m "$(printf 'Add downstream\n\nDerives-From: docs/adr/0001-one.md\n')" \
    && printf 'changed\n' >> docs/adr/0001-one.md && g add -A \
    && g commit -q -m "$(printf 'Revise\n\nRevises: docs/adr/0001-one.md\n'; [ -n "${VERDICT:-}" ] && printf '%s\n' "$VERDICT")" )
  echo "$wd"
}

t "gate: a revision whose only downstream goes unverdicted is auto-deferred, reaching the decision path (plan 0021)"
  wd="$(revision "$R/rev1" --remote origin)"; githubify "$R/rev1"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  assert_contains "$out" "pull/7"; assert_contains "$out" "human"
  assert_eq "$(cd "$R/rev1" && git rev-parse adr-0001-one)" "$(bare_tip "$R/rev1" adr-0001-one)" "branch must be pushed at the same SHA"
  assert_eq "adr-0001-one" "$(cd "$R/rev1" && git rev-parse --abbrev-ref HEAD)" "primary checkout must stay on the branch"
  [ -n "$(cd "$R/rev1" && git for-each-ref refs/heads/adr-0001-one)" ] || fail "branch removed on a decision"
  defers="$(cd "$R/rev1" && git log --format='%(trailers:key=Defers,valueonly)' dev..adr-0001-one | sed '/^$/d')"
  assert_contains "$defers" "plans/9001-downstream.md docs/adr/0001-one.md until a plan derives from it"

t "gate: a Confirms verdict for the downstream passes the gate (reaches the decision path, not exit 2)"
  wd="$(VERDICT="Confirms: plans/9001-downstream.md" revision "$R/rev2")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the gate refused a Confirms verdict: $out" ;; esac

t "gate: a Reconciles verdict for the downstream passes the gate"
  wd="$(VERDICT="Reconciles: plans/9001-downstream.md" revision "$R/rev3")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the gate refused a Reconciles verdict: $out" ;; esac

t "gate: a Defers verdict passes, its free-text condition parsed only for the leading path"
  wd="$(VERDICT="Defers: plans/9001-downstream.md until docs/adr/0007-x.md lands" revision "$R/rev4")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the gate refused a Defers verdict: $out" ;; esac
  # a second, differently-worded condition proves the remainder is opaque
  wd="$(VERDICT="Defers: plans/9001-downstream.md blocked on the seed-126 discharge work" revision "$R/rev5")"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the gate parsed the Defers condition instead of ignoring it: $out" ;; esac

t "gate: a downstream that has left the tree needs no verdict"
  wd="$(revision "$R/rev6")"
  (cd "$wd" && g rm -q plans/9001-downstream.md && g commit -q -m "$(printf 'Complete the downstream\n\nCompletes: plans/9001-downstream.md\n')")
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the gate demanded a verdict for a completed downstream: $out" ;; esac

t "gate: a new-ADR decision with no Revises does not fire the gate"
  wd="$(ADRPATH=docs/adr/0002-x.md artefact "$R/rev7" --where worktree)"
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the gate fired on a new-ADR decision: $out" ;; esac

t "gate: two revised ADRs: the unverdicted downstream is auto-deferred against its own revised ADR, reaching the decision path (plan 0021)"
  fixture "$R/rev8" --trunk dev >/dev/null
  (cd "$R/rev8" && printf -- '---\ntitle: three\n---\n' > docs/adr/0003-three.md && g add docs/adr/0003-three.md && g commit -q -m "fixture: a second ADR")
  out="$(cd "$R/rev8" && bash "$SCRIPT" begin docs/adr/0001-one.md 2>&1)"; wd="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  ( cd "$wd" && mkdir -p plans \
    && printf -- '---\ntitle: d1\n---\n' > plans/9001-downstream.md && g add plans/9001-downstream.md && g commit -q -m "$(printf 'Add d1\n\nDerives-From: docs/adr/0001-one.md\n')" \
    && printf -- '---\ntitle: d2\n---\n' > plans/9002-two.md && g add plans/9002-two.md && g commit -q -m "$(printf 'Add d2\n\nDerives-From: docs/adr/0003-three.md\n')" \
    && printf 'c1\n' >> docs/adr/0001-one.md && printf 'c3\n' >> docs/adr/0003-three.md && g add -A \
    && g commit -q -m "$(printf 'Revise both\n\nConfirms: plans/9001-downstream.md\nRevises: docs/adr/0001-one.md\nRevises: docs/adr/0003-three.md\n')" )
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the gate refused once 9002 was auto-deferred against its own revised ADR: $out" ;; esac
  defers="$(cd "$R/rev8" && git log --format='%(trailers:key=Defers,valueonly)' dev..adr-0001-one | sed '/^$/d')"
  assert_contains "$defers" "plans/9002-two.md docs/adr/0003-three.md until a plan derives from it"
  case "$defers" in *"plans/9001-downstream.md "*) fail "9001 already carries a Confirms and must not be auto-deferred too: $defers" ;; esac
  # with both verdicts recorded, the gate passes
  (cd "$wd" && g commit -q --allow-empty -m "$(printf 'Confirm the second downstream\n\nConfirms: plans/9002-two.md\n')")
  out="$(land "$wd"; echo "exit=$?")"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the gate refused with both downstreams verdicted: $out" ;; esac

t "gate: the history script absent is a hard stop, before the verdict logic"
  wd="$(VERDICT="Confirms: plans/9001-downstream.md" revision "$R/rev9")"   # verdict-complete: would otherwise pass
  mkdir -p "$R/nohist" && cp "$SCRIPT" "$R/nohist/git-workflow" && chmod +x "$R/nohist/git-workflow"
  out="$( (cd "$wd" && bash "$R/nohist/git-workflow" land 2>&1); echo "exit=$?" )"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "history/scripts/history.sh"
  assert_contains "$out" "nohist"
  assert_eq "adr-0001-one" "$(cd "$R/rev9" && git rev-parse --abbrev-ref HEAD)" "the hard stop must change nothing"
  [ -n "$(cd "$R/rev9" && git for-each-ref refs/heads/adr-0001-one)" ] || fail "branch removed on the hard stop"

# installed DIR — copy git-workflow and the sibling history script into
# DIR/skills/<skill>/scripts/ with mode 0644, as `tessl plugin pack` and an
# install leave them (the pack drops the executable bit). Echoes the path
# of the installed git-workflow script.
installed() {
  local d="$1" src; src="$(cd "$(dirname "$SCRIPT")" && pwd)"
  mkdir -p "$d/skills/git-workflow/scripts" "$d/skills/history/scripts"
  cp "$SCRIPT" "$d/skills/git-workflow/scripts/git-workflow.sh"
  cp "$src/../../history/scripts/history.sh" "$d/skills/history/scripts/history.sh"
  chmod 0644 "$d/skills/git-workflow/scripts/git-workflow.sh" "$d/skills/history/scripts/history.sh"
  echo "$d/skills/git-workflow/scripts/git-workflow.sh"
}

t "installed copy: a history script without the executable bit still lets a new-ADR decision land to the decision path"
  wd="$(ADRPATH=docs/adr/0002-x.md artefact "$R/inst1" --where worktree)"
  gw="$(installed "$R/inst1-plugin")"
  out="$( (cd "$wd" && bash "$gw" land 2>&1); echo "exit=$?" )"
  assert_contains "$out" "exit=3"
  case "$out" in *"not an executable"*|*"not a regular file"*) fail "land refused an installed (0644) history script: $out" ;; esac

t "installed copy: a history script without the executable bit still runs the revision gate"
  wd="$(VERDICT="Confirms: plans/9001-downstream.md" revision "$R/inst2")"
  gw="$(installed "$R/inst2-plugin")"
  out="$( (cd "$wd" && bash "$gw" land 2>&1); echo "exit=$?" )"
  assert_contains "$out" "exit=3"
  case "$out" in *exit=2*) fail "the gate refused an installed (0644) history script: $out" ;; esac
