# begin: name the branch from the artefact path, branch in place or into a
# worktree from the trunk, bootstrap the worktree, and touch nothing else.

R="$TMP_ROOT/begin"
begin() { local d="$1"; shift; (cd "$d" && bash "$SCRIPT" begin "$@" 2>&1); }
line() { printf '%s\n' "$1" | grep "^$2=" | head -1; }
tip() { (cd "$1" && git rev-parse "$2"); }
bare_tip() { git --git-dir="$1/.origin/repo.git" rev-parse "$2" 2>/dev/null; }
has_branch() { (cd "$1" && git rev-parse --verify --quiet "refs/heads/$2" >/dev/null); }
# advance_origin DIR — put a commit on dev in DIR's bare origin that DIR lacks.
# The bare repository's HEAD names no branch, so the clone switches to dev.
advance_origin() {
  local c; c="$(mktemp -d "$TMP_ROOT/advance.XXXXXX")"
  git clone -q "$1/.origin/repo.git" "$c/c" 2>/dev/null && (cd "$c/c" && g switch -q dev \
    && printf 'remote\n' >> REMOTE-ONLY.md && g add REMOTE-ONLY.md && g commit -q -m "remote: ahead" && g push -q origin dev)
}

t "naming: docs/adr/NNNN-slug.md -> adr-NNNN-slug"
  fixture "$R/n1" --trunk dev >/dev/null
  out="$(begin "$R/n1" docs/adr/0007-sample-heartbeats.md)"
  assert_eq "branch=adr-0007-sample-heartbeats" "$(line "$out" branch)" "$out"

t "naming: plans/NNNN-slug.md -> plan-NNNN-slug"
  fixture "$R/n2" --trunk dev >/dev/null
  out="$(begin "$R/n2" plans/0005-script.md)"
  assert_eq "branch=plan-0005-script" "$(line "$out" branch)" "$out"

t "naming: docs/discovery/NNNN-slug.md -> discovery-NNNN-slug"
  fixture "$R/n3" --trunk dev >/dev/null
  out="$(begin "$R/n3" docs/discovery/0002-thing.md)"
  assert_eq "branch=discovery-0002-thing" "$(line "$out" branch)" "$out"

t "naming: skills/<name>/SKILL.md -> skill-<name>"
  fixture "$R/n4" --trunk dev >/dev/null
  out="$(begin "$R/n4" skills/history/SKILL.md)"
  assert_eq "branch=skill-history" "$(line "$out" branch)" "$out"

t "naming: an ungoverned path needs --slug and gives chore-<slug>"
  fixture "$R/n5" --trunk dev >/dev/null
  out="$( (cd "$R/n5" && bash "$SCRIPT" begin src/thing.py 2>&1); echo "exit=$?" )"
  assert_contains "$out" "exit=2"; assert_contains "$out" "slug"
  assert_eq "dev" "$(cd "$R/n5" && git rev-parse --abbrev-ref HEAD)" "refusal must change nothing"
  out="$(begin "$R/n5" src/thing.py --slug fix-thing)"
  assert_eq "branch=chore-fix-thing" "$(line "$out" branch)" "$out"

t "in place: on the trunk and clean, the primary checkout moves to the new branch"
  fixture "$R/p1" --trunk dev --config >/dev/null
  out="$(begin "$R/p1" docs/adr/0002-x.md)"
  assert_eq "trunk=dev" "$(line "$out" trunk)" "$out"
  assert_eq "dir=$(cd "$R/p1" && pwd -P)" "$(line "$out" dir)" "$out"
  assert_eq "adr-0002-x" "$(cd "$R/p1" && git rev-parse --abbrev-ref HEAD)"
  assert_eq "$(tip "$R/p1" dev)" "$(tip "$R/p1" adr-0002-x)" "branch must start at the trunk tip"
  assert_eq "0" "$(cd "$R/p1" && git worktree list | grep -c worktrees)" "no worktree in place"

t "worktree: on another branch, the worktree forks from the trunk, not from HEAD"
  fixture "$R/w1" --trunk dev --branch topic --config >/dev/null
  (cd "$R/w1" && printf '.worktrees/\n' >> .gitignore && g add .gitignore && g commit -q -m "ignore worktrees" && g switch -q topic)
  out="$(begin "$R/w1" docs/adr/0002-x.md)"
  wt="$R/w1/.worktrees/adr-0002-x"
  assert_eq "dir=$(cd "$R/w1" && pwd -P)/.worktrees/adr-0002-x" "$(line "$out" dir)" "$out"
  [ -d "$wt" ] || fail "worktree directory missing"
  assert_eq "adr-0002-x" "$(cd "$wt" && git rev-parse --abbrev-ref HEAD)"
  assert_eq "$(tip "$R/w1" dev)" "$(cd "$wt" && git rev-parse HEAD~0 2>/dev/null | head -1)" "worktree HEAD must be the trunk tip (no gitignore commit expected here)"
  [ -f "$wt/TRUNK-ONLY.md" ] || fail "trunk-only file missing: forked from the wrong branch"
  [ -f "$wt/BRANCH-ONLY.md" ] && fail "branch-only file present: forked from HEAD, not the trunk"
  assert_eq "topic" "$(cd "$R/w1" && git rev-parse --abbrev-ref HEAD)" "primary checkout must stay where it was"
  # this fixture already ignores .worktrees/ so no bookkeeping commit is made
  true

t "worktree: on the trunk but dirty, no checkout line in the primary reflog and dirt untouched"
  fixture "$R/w2" --trunk dev --dirty --config >/dev/null
  (cd "$R/w2" && printf '.worktrees/\n' >> .gitignore && g add .gitignore && g commit -q -m "ignore worktrees" && printf 'TODO: unfinished edit\n' >> README.md)
  before="$(cd "$R/w2" && git status --porcelain | sort)"
  begin "$R/w2" docs/adr/0002-x.md >/dev/null
  [ -d "$R/w2/.worktrees/adr-0002-x" ] || fail "worktree not created"
  assert_eq "adr-0002-x" "$(cd "$R/w2/.worktrees/adr-0002-x" 2>/dev/null && git rev-parse --abbrev-ref HEAD)" "worktree not on the branch"
  assert_eq "0" "$(cd "$R/w2" && grep -c 'checkout: moving from dev' .git/logs/HEAD)" "primary reflog gained a checkout line"
  assert_eq "dev" "$(cd "$R/w2" && git rev-parse --abbrev-ref HEAD)"
  assert_eq "$before" "$(cd "$R/w2" && git status --porcelain | grep -v worktrees | sort)" "dirt must be exactly as it was"
  assert_contains "$(cd "$R/w2" && git status --porcelain)" " M README.md"
  assert_contains "$(cd "$R/w2" && git status --porcelain)" "?? notes.txt"

t "bootstrap: config files copied, built dependencies left behind, base checkout intact"
  fixture "$R/w3" --trunk dev --branch topic --ignored >/dev/null
  (cd "$R/w3" && printf 'KEY=1\n' > .env && printf '{}\n' > .mcp.json && g switch -q topic)
  begin "$R/w3" docs/adr/0002-x.md >/dev/null
  wt="$R/w3/.worktrees/adr-0002-x"
  [ -f "$wt/.claude/settings.local.json" ] || fail ".claude not copied"
  [ -f "$wt/.env" ] || fail ".env not copied"
  [ -f "$wt/.mcp.json" ] || fail ".mcp.json not copied"
  [ -d "$wt/.venv" ] && fail ".venv copied"
  [ -d "$wt/node_modules" ] && fail "node_modules copied"
  [ -f "$R/w3/.claude/settings.local.json" ] || fail ".claude missing from base checkout: moved, not copied"
  [ -d "$R/w3/.venv" ] || fail ".venv missing from base checkout"
  [ -d "$R/w3/node_modules" ] || fail "node_modules missing from base checkout"
  true

t "bookkeeping: the .worktrees/ line is left uncommitted in the worktree when missing"
  fixture "$R/w4" --trunk dev --dirty >/dev/null
  before="$(cd "$R/w4" && git status --porcelain | sort)"
  out="$(begin "$R/w4" docs/adr/0002-x.md)"
  wt="$R/w4/.worktrees/adr-0002-x"
  (cd "$wt" && git check-ignore -q .worktrees/probe) || fail ".worktrees/ not ignored in the worktree"
  assert_eq "1" "$(cd "$wt" && grep -c '^\.worktrees/$' .gitignore)" "the worktree's .gitignore must carry the line once"
  assert_eq "0" "$(cd "$wt" && git rev-list --count dev..HEAD)" "begin must make no commit"
  assert_eq " M .gitignore" "$(cd "$wt" && git status --porcelain)" "the line must be an uncommitted change and the only one"
  assert_eq "include=.gitignore" "$(line "$out" include)" "$out"
  assert_eq "0" "$(cd "$R/w4" && grep -c '^\.worktrees/$' .gitignore)" "primary checkout's .gitignore must be untouched"
  assert_eq "$before" "$(cd "$R/w4" && git status --porcelain | grep -v worktrees | sort)" "primary dirt must be exactly as it was"
  assert_eq "$(tip "$R/w4" dev)" "$(cd "$R/w4" && git rev-parse dev)" "trunk must not move"

t "bookkeeping: no commit when the line already exists"
  fixture "$R/w5" --trunk dev --branch topic >/dev/null
  (cd "$R/w5" && printf '.worktrees/\n' >> .gitignore && g add .gitignore && g commit -q -m "ignore worktrees" && g switch -q topic)
  out="$(begin "$R/w5" docs/adr/0002-x.md)"
  assert_eq "0" "$(cd "$R/w5/.worktrees/adr-0002-x" && git rev-list --count dev..HEAD)"
  assert_eq "" "$(line "$out" include)" "no include= line when nothing was added: $out"
  assert_eq "" "$(cd "$R/w5/.worktrees/adr-0002-x" && git status --porcelain)" "worktree must be clean"

t "bootstrap: a tracked .claude/ is filled in with untracked files, not nested, and tracked files are not overwritten"
  fixture "$R/w6" --trunk dev --ignored >/dev/null
  (cd "$R/w6" && printf '.worktrees/\n' >> .gitignore && mkdir -p .claude/skills && printf 'tracked\n' > .claude/skills/x.md \
    && g add .gitignore && g add -f .claude/skills/x.md && g commit -q -m "track a project skill" \
    && printf 'local edit\n' > .claude/skills/x.md)
  begin "$R/w6" docs/adr/0002-x.md >/dev/null
  wt="$R/w6/.worktrees/adr-0002-x"
  [ -f "$wt/.claude/settings.local.json" ] || fail ".claude/settings.local.json not at its own path in the worktree"
  assert_eq "$(cat "$R/w6/.claude/settings.local.json")" "$(cat "$wt/.claude/settings.local.json" 2>/dev/null)" "settings copied with different content"
  [ -e "$wt/.claude/.claude" ] && fail ".claude copied inside itself"
  assert_eq "tracked" "$(cat "$wt/.claude/skills/x.md" 2>/dev/null)" "tracked file overwritten by the primary's edit"
  assert_eq "" "$(cd "$wt" && git status --porcelain)" "worktree must be clean after bootstrap"
  true

t "refusal: the branch already exists"
  fixture "$R/r1" --trunk dev --branch adr-0002-x >/dev/null
  out="$( (cd "$R/r1" && bash "$SCRIPT" begin docs/adr/0002-x.md 2>&1); echo "exit=$?" )"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "already exists"
  assert_eq "dev" "$(cd "$R/r1" && git rev-parse --abbrev-ref HEAD)"
  [ -d "$R/r1/.worktrees" ] && fail "worktree created despite refusal"
  true

t "refusal: check's failures propagate (no trunk resolves)"
  fixture "$R/r2" --trunk main >/dev/null
  out="$( (cd "$R/r2" && bash "$SCRIPT" begin docs/adr/0002-x.md 2>&1); echo "exit=$?" )"
  assert_contains "$out" "exit=2"
  assert_contains "$out" "refs/heads/dev"

t "output: trunk, branch and dir lines are all printed"
  fixture "$R/o1" --trunk dev >/dev/null
  out="$(begin "$R/o1" docs/adr/0002-x.md)"
  for k in trunk branch dir; do [ -n "$(line "$out" $k)" ] || fail "missing $k="; done

t "trunk: remote ahead, primary on the trunk and clean -> local trunk fast-forwarded, branch from the remote's tip"
  fixture "$R/k1" --trunk dev --remote origin >/dev/null; advance_origin "$R/k1"
  out="$(begin "$R/k1" docs/adr/0002-x.md; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  assert_eq "$(bare_tip "$R/k1" dev)" "$(tip "$R/k1" dev)" "local dev not fast-forwarded to origin's: $out"
  assert_eq "$(bare_tip "$R/k1" dev)" "$(tip "$R/k1" adr-0002-x)" "branch must start at origin's tip"

t "trunk: remote ahead, primary parked off the trunk -> local trunk moved by ref, primary stays, worktree from the remote's tip"
  fixture "$R/k2" --trunk dev --branch topic --remote origin >/dev/null; (cd "$R/k2" && g switch -q topic); advance_origin "$R/k2"
  out="$(begin "$R/k2" docs/adr/0002-x.md; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  assert_eq "$(bare_tip "$R/k2" dev)" "$(tip "$R/k2" dev)" "local dev not moved to origin's: $out"
  assert_eq "topic" "$(cd "$R/k2" && git rev-parse --abbrev-ref HEAD)" "primary checkout must stay where it was"
  assert_eq "$(bare_tip "$R/k2" dev)" "$(cd "$R/k2/.worktrees/adr-0002-x" 2>/dev/null && git rev-parse HEAD)" "worktree branch must start at origin's tip"

t "trunk: the fetch fails -> exit 1, could not fetch, no branch and no worktree"
  fixture "$R/k3" --trunk dev --remote origin --remote-url /nonexistent/repo.git >/dev/null
  out="$(begin "$R/k3" docs/adr/0002-x.md; echo "exit=$?")"
  assert_contains "$out" "exit=1"
  assert_contains "$out" "could not fetch"
  has_branch "$R/k3" adr-0002-x && fail "branch created despite the failed fetch"
  [ -d "$R/k3/.worktrees" ] && fail "worktree created despite the failed fetch"
  true

t "trunk: local trunk has commits the remote lacks, ahead or diverged -> exit 1, trunk unchanged, no branch"
  fixture "$R/k4" --trunk dev --remote origin >/dev/null
  (cd "$R/k4" && printf 'local\n' > LOCAL-ONLY.md && g add LOCAL-ONLY.md && g commit -q -m "local: ahead")
  dev_before="$(tip "$R/k4" dev)"
  out="$(begin "$R/k4" docs/adr/0002-x.md; echo "exit=$?")"
  assert_contains "$out" "exit=1" "ahead: $out"
  assert_contains "$out" "could not fast-forward" "ahead: $out"
  assert_contains "$out" "local dev has commits origin/dev lacks" "ahead: $out"
  assert_eq "$dev_before" "$(tip "$R/k4" dev)" "ahead: local dev moved"
  has_branch "$R/k4" adr-0002-x && fail "ahead: branch created"
  # the repeat, diverged, on a fresh fixture so it does not see the first half's outcome
  fixture "$R/k4d" --trunk dev --remote origin >/dev/null; advance_origin "$R/k4d"
  (cd "$R/k4d" && printf 'local\n' > LOCAL-ONLY.md && g add LOCAL-ONLY.md && g commit -q -m "local: ahead")
  dev_before="$(tip "$R/k4d" dev)"
  out="$(begin "$R/k4d" docs/adr/0002-x.md; echo "exit=$?")"
  assert_contains "$out" "exit=1" "diverged: $out"
  assert_contains "$out" "could not fast-forward" "diverged: $out"
  assert_contains "$out" "local dev has commits origin/dev lacks" "diverged: $out"
  assert_eq "$dev_before" "$(tip "$R/k4d" dev)" "diverged: local dev moved"
  has_branch "$R/k4d" adr-0002-x && fail "diverged: branch created"
  true

t "trunk: primary on the trunk with a tracked change, remote ahead -> exit 1, trunk and file unchanged, no branch"
  fixture "$R/k5" --trunk dev --remote origin >/dev/null; advance_origin "$R/k5"
  (cd "$R/k5" && printf 'TODO: unfinished edit\n' >> README.md)
  dev_before="$(tip "$R/k5" dev)"; readme_before="$(cat "$R/k5/README.md")"
  out="$(begin "$R/k5" docs/adr/0002-x.md; echo "exit=$?")"
  assert_contains "$out" "exit=1"
  assert_contains "$out" "could not fast-forward"
  assert_eq "$dev_before" "$(tip "$R/k5" dev)" "local dev moved under a dirty primary"
  assert_eq "$readme_before" "$(cat "$R/k5/README.md")" "the primary's tracked change was touched"
  has_branch "$R/k5" adr-0002-x && fail "branch created"
  true

t "trunk: trunk checked out in another worktree, remote ahead -> exit 1, no branch, that worktree untouched"
  fixture "$R/k6" --trunk dev --branch topic --remote origin >/dev/null
  (cd "$R/k6" && g switch -q topic && g worktree add -q "$R/trunk-wt" dev); advance_origin "$R/k6"
  wt_before="$(cd "$R/trunk-wt" && git rev-parse HEAD)"
  out="$(begin "$R/k6" docs/adr/0002-x.md; echo "exit=$?")"
  assert_contains "$out" "exit=1"
  assert_contains "$out" "could not fast-forward"
  has_branch "$R/k6" adr-0002-x && fail "branch created"
  assert_eq "$wt_before" "$(cd "$R/trunk-wt" && git rev-parse HEAD)" "the other worktree's dev moved"
  assert_eq "dev" "$(cd "$R/trunk-wt" && git rev-parse --abbrev-ref HEAD)"

# --- Step 2: the advisory downstream worklist (ADR 0011, plan 0017) ----------

t "worklist: a revision of an on-trunk ADR surfaces its downstream advisorily, in place"
  fixture "$R/wl1" --trunk dev >/dev/null
  (cd "$R/wl1" && mkdir -p plans && printf -- '---\ntitle: d\n---\n' > plans/9001-downstream.md && g add plans/9001-downstream.md \
    && g commit -q -m "$(printf 'Add downstream\n\nDerives-From: docs/adr/0001-one.md\n')")
  out="$(begin "$R/wl1" docs/adr/0001-one.md; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  assert_contains "$out" "worklist:"
  assert_contains "$out" "plans/9001-downstream.md"
  for k in trunk branch dir; do [ -n "$(line "$out" $k)" ] || fail "missing $k= alongside the worklist"; done

t "worklist: a new ADR not on the trunk surfaces no worklist"
  fixture "$R/wl2" --trunk dev >/dev/null
  out="$(begin "$R/wl2" docs/adr/0002-x.md; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  case "$out" in *worklist:*) fail "a new ADR must surface no worklist: $out" ;; esac

t "worklist: the advisory block prints on the worktree path too, and never blocks begin"
  fixture "$R/wl3" --trunk dev --branch topic >/dev/null
  (cd "$R/wl3" && mkdir -p plans && printf -- '---\ntitle: d\n---\n' > plans/9001-downstream.md && g add plans/9001-downstream.md \
    && g commit -q -m "$(printf 'Add downstream\n\nDerives-From: docs/adr/0001-one.md\n')" && g switch -q topic)
  out="$(begin "$R/wl3" docs/adr/0001-one.md; echo "exit=$?")"
  assert_contains "$out" "exit=0"
  assert_contains "$out" "worklist:"
  assert_contains "$out" "plans/9001-downstream.md"
  [ -d "$R/wl3/.worktrees/adr-0001-one" ] || fail "worktree not created"

t "worklist: an installed history script without the executable bit still surfaces the worklist"
  fixture "$R/wl4" --trunk dev >/dev/null
  (cd "$R/wl4" && mkdir -p plans && printf -- '---\ntitle: d\n---\n' > plans/9001-downstream.md && g add plans/9001-downstream.md \
    && g commit -q -m "$(printf 'Add downstream\n\nDerives-From: docs/adr/0001-one.md\n')")
  src="$(cd "$(dirname "$SCRIPT")" && pwd)"
  mkdir -p "$R/wl4-plugin/skills/git-workflow/scripts" "$R/wl4-plugin/skills/history/scripts"
  cp "$SCRIPT" "$R/wl4-plugin/skills/git-workflow/scripts/git-workflow.sh"
  cp "$src/../../history/scripts/history.sh" "$R/wl4-plugin/skills/history/scripts/history.sh"
  chmod 0644 "$R/wl4-plugin/skills/git-workflow/scripts/git-workflow.sh" "$R/wl4-plugin/skills/history/scripts/history.sh"
  out="$( (cd "$R/wl4" && bash "$R/wl4-plugin/skills/git-workflow/scripts/git-workflow.sh" begin docs/adr/0001-one.md 2>&1); echo "exit=$?" )"
  assert_contains "$out" "exit=0"
  assert_contains "$out" "worklist:"
  assert_contains "$out" "plans/9001-downstream.md"
