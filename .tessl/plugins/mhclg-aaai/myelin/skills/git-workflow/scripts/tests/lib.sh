#!/usr/bin/env bash
# Test helpers for the git-workflow script.
#
# Sourced by every test file. Provides:
#   t NAME            begin a test; increments the count
#   pass / fail MSG   record the outcome of the current test
#   assert_eq EXPECTED ACTUAL [MSG]
#   assert_contains HAYSTACK NEEDLE [MSG]
#   assert_exit CODE CMD...      run CMD, assert its exit code
#   fixture DIR [OPTIONS]        build a git repository to test against
#
# fixture options:
#   --trunk NAME      the branch the initial commit lands on (default main)
#   --branch NAME     an extra branch off trunk carrying one more commit
#   --remote NAME     a bare repository at DIR/.origin/repo.git added as NAME,
#                     with every branch pushed and NAME/HEAD set to the trunk
#   --remote-url URL  use URL for the remote instead of the bare path
#   --dirty           leave README.md modified and notes.txt untracked
#   --ignored         create .venv/, node_modules/ and .claude/settings.local.json,
#                     all gitignored, with content
#   --config          set workflow.trunk=main and init.defaultBranch=main, and
#                     write a CONTRIBUTING.md that says to cut from main
#
# The helpers never touch the caller's repository: every fixture is under
# a directory the caller passes, normally inside $TMPDIR.

set -u

# The script under test commits in worktrees; give it an identity.
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

SCRIPT="${SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/git-workflow.sh}"
TESTS_RUN=0
TESTS_FAILED=0
_CURRENT=""
_FAILED_THIS=0

t() {
  _CURRENT="$1"
  _FAILED_THIS=0
  TESTS_RUN=$((TESTS_RUN + 1))
}

fail() {
  if [ "$_FAILED_THIS" -eq 0 ]; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _FAILED_THIS=1
  fi
  printf 'FAIL %s: %s\n' "$_CURRENT" "$1" >&2
}

assert_eq() {
  if [ "$1" != "$2" ]; then fail "${3:-expected [$1] got [$2]}"; fi
}

assert_contains() {
  case "$1" in *"$2"*) ;; *) fail "${3:-output lacks [$2]}" ;; esac
}

assert_exit() {
  local want="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" != "$want" ]; then fail "expected exit $want got $got: $*"; fi
}

# git with a fixed identity and no global config leakage.
g() { git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }

fixture() {
  local dir="$1"; shift
  local trunk=main branch="" remote="" remote_url="" dirty=0 ignored=0 config=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --trunk) trunk="$2"; shift 2 ;;
      --branch) branch="$2"; shift 2 ;;
      --remote) remote="$2"; shift 2 ;;
      --remote-url) remote_url="$2"; shift 2 ;;
      --dirty) dirty=1; shift ;;
      --ignored) ignored=1; shift ;;
      --config) config=1; shift ;;
      *) echo "fixture: unknown option $1" >&2; return 2 ;;
    esac
  done
  rm -rf "$dir" && mkdir -p "$dir" && cd "$dir" || return 2
  g init -q -b "$trunk" . || return 2
  printf 'node_modules/\nvenv/\n.claude/\n*.log\n' > .gitignore
  printf '# fixture\n' > README.md
  mkdir -p docs/adr docs/discovery
  printf -- '---\ntitle: one\n---\n' > docs/adr/0001-one.md
  printf -- '---\ntitle: note\n---\n' > docs/discovery/0001-note.md
  g add -A && g commit -q -m "fixture: initial" || return 2
  printf 'only on %s\n' "$trunk" > TRUNK-ONLY.md && g add TRUNK-ONLY.md && g commit -q -m "fixture: trunk-only file" || return 2
  if [ -n "$branch" ]; then
    g switch -q -c "$branch" && printf 'on %s\n' "$branch" > BRANCH-ONLY.md && g add BRANCH-ONLY.md && g commit -q -m "fixture: branch-only file" && g switch -q "$trunk" || return 2
  fi
  if [ -n "$remote" ]; then
    local url="$remote_url"
    if [ -z "$url" ]; then
      mkdir -p .origin && g init -q --bare .origin/repo.git && url="$(pwd)/.origin/repo.git"
      printf '.origin/\n' >> .gitignore && g add .gitignore && g commit -q -m "fixture: ignore .origin" || return 2
    fi
    g remote add "$remote" "$url" || return 2
    if [ -z "$remote_url" ]; then
      g push -q "$remote" --all && g remote set-head "$remote" "$trunk" || return 2
    fi
  fi
  if [ "$config" -eq 1 ]; then
    g config workflow.trunk main && g config init.defaultBranch main
    printf 'Cut branches from main. Name them feature/<initials>-<desc>. Squash-merge via a pull request.\n' > CONTRIBUTING.md
    g add CONTRIBUTING.md && g commit -q -m "fixture: contributing guide" || return 2
  fi
  if [ "$ignored" -eq 1 ]; then
    mkdir -p .venv/bin node_modules/left-pad .claude
    printf 'home = /usr\n' > .venv/pyvenv.cfg; printf 'x\n' > .venv/bin/python
    printf '{}\n' > node_modules/left-pad/package.json
    printf '{"permissions":{"allow":["Bash(git *)"]}}\n' > .claude/settings.local.json
    grep -q '^\.venv/$' .gitignore || { printf '.venv/\n' >> .gitignore && g add .gitignore && g commit -q -m "fixture: ignore .venv" || return 2; }
  fi
  if [ "$dirty" -eq 1 ]; then
    printf 'TODO: unfinished edit\n' >> README.md
    printf 'scratch\n' > notes.txt
  fi
  return 0
}

report() {
  printf '%d tests, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
