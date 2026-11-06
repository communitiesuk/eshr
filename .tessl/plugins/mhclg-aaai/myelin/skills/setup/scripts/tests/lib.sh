#!/usr/bin/env bash
# Test helpers for the setup check script.
#
# Sourced by every test file. Provides:
#   t NAME                       begin a test; increments the count
#   fail MSG                     record a failure of the current test
#   assert_eq EXPECTED ACTUAL [MSG]
#   assert_contains HAYSTACK NEEDLE [MSG]
#   assert_not_contains HAYSTACK NEEDLE [MSG]
#   newrepo                      a fresh git repo on `dev` with one commit
#                                (a resolvable trunk), and a sandbox bin
#   newrepo_notrunk              a fresh repo on a feature branch with no
#                                dev/develop and no origin/HEAD
#   add_remote                   give the current repo a remote named origin
#   fake_gh [REPO_JSON]          put a stub `gh` on the sandbox PATH that
#                                logs its argv to $GHLOG and, for `gh api`,
#                                prints REPO_JSON (default `{}`)
#   no_gh                        remove gh from the sandbox PATH
#   run_check [ARGS...]          run check with PATH limited to the sandbox
#                                (git, jq, bash, and gh when faked); sets
#                                OUT (stdout) and OUT_STATUS
#
# The sandbox bin is how a test controls host-CLI presence deterministically
# on a machine that has gh installed: the check runs with PATH pointing only
# at the sandbox, so `command -v gh` finds a stub or nothing as the test
# chooses. Everything is built under $TMP_ROOT, which run.sh creates per file.

set -u

SCRIPT="${SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/check.sh}"
TESTS_RUN=0
TESTS_FAILED=0
_CURRENT=""
_FAILED_THIS=0
_REPO_N=0
SBIN=""
GHLOG=""

t() { _CURRENT="$1"; _FAILED_THIS=0; TESTS_RUN=$((TESTS_RUN + 1)); }

fail() {
  if [ "$_FAILED_THIS" -eq 0 ]; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _FAILED_THIS=1
  fi
  printf 'FAIL %s: %s\n' "$_CURRENT" "$1" >&2
}

assert_eq() { if [ "$1" != "$2" ]; then fail "${3:-expected [$1] got [$2]}"; fi; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "${3:-output lacks [$2]}" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "${3:-output has [$2]}" ;; esac; }

# A sandbox bin holding only the real tools the check needs (git, jq,
# bash) — gh is added on demand by fake_gh. run_check points PATH here.
_sandbox() {
  SBIN="$TMP_ROOT/sbin-$_REPO_N"
  mkdir -p "$SBIN"
  local tool
  for tool in git jq bash; do ln -sf "$(command -v "$tool")" "$SBIN/$tool"; done
  rm -f "$SBIN/gh"
}

_initrepo() {  # $1 = branch to start HEAD on
  _REPO_N=$((_REPO_N + 1))
  local d="$TMP_ROOT/repo-$_REPO_N"
  mkdir -p "$d"
  cd "$d" || return 1
  git init -q .
  git symbolic-ref HEAD "refs/heads/$1"
  git config --local user.name "Setup Tests"
  git config --local user.email "tests@setup.invalid"
  git config --local commit.gpgsign false
  printf 'x\n' > file
  git add file
  git commit -q -m "init"
  _sandbox
}

newrepo() { _initrepo dev; }
newrepo_notrunk() { _initrepo feature; }

add_remote() { git remote add origin "$TMP_ROOT/origin-$_REPO_N.git"; }

fake_gh() {
  local json="${1:-{\}}"
  GHLOG="$TMP_ROOT/gh-$_REPO_N.log"
  : > "$GHLOG"
  cat > "$SBIN/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GHLOG"
if [ "\${1:-}" = api ]; then printf '%s' '$json'; fi
EOF
  chmod +x "$SBIN/gh"
}

no_gh() { rm -f "$SBIN/gh"; }

run_check() {
  OUT_STATUS=0
  OUT="$(PATH="$SBIN" bash "$SCRIPT" "$@" 2>"$TMP_ROOT/stderr")" || OUT_STATUS=$?
}
