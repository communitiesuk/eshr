#!/usr/bin/env bash
# Finding the transcript, and the exit codes. Sourced by run.sh after lib.sh.

t "8. the project path is encoded with every non-alphanumeric as -"
mkdir -p "$CFG/projects/-x-proj--worktrees-b"
cp "$FIXTURES/human.jsonl.txt" "$CFG/projects/-x-proj--worktrees-b/sess-8.jsonl"
dialogue sess-8 /x/proj/.worktrees/b "$TMP_ROOT/o8.md"
assert_eq 0 "$OUT_STATUS"
assert_eq "Mode: adapter (claude-code)" "$(sed -n 2p "$TMP_ROOT/o8.md" 2>/dev/null)"

t "9. a unique match elsewhere is found; two matches are not found"
mkdir -p "$CFG/projects/-somewhere-else"
cp "$FIXTURES/human.jsonl.txt" "$CFG/projects/-somewhere-else/sess-9.jsonl"
dialogue sess-9 /not/the/same "$TMP_ROOT/o9.md"
assert_eq 0 "$OUT_STATUS" "unique match not found"
assert_eq "# Dialogue" "$(sed -n 1p "$TMP_ROOT/o9.md" 2>/dev/null)"
mkdir -p "$CFG/projects/-a-second-place"
cp "$FIXTURES/human.jsonl.txt" "$CFG/projects/-a-second-place/sess-9.jsonl"
rm -f "$TMP_ROOT/o9b.md"
dialogue sess-9 /not/the/same "$TMP_ROOT/o9b.md"
assert_eq 1 "$OUT_STATUS" "two matches should be not found"
[ -e "$TMP_ROOT/o9b.md" ] && fail "out-file written although two matches"

t "10. not found exits 1 and writes nothing; missing arguments exit 2; --help exits 0"
rm -f "$TMP_ROOT/o10.md"
dialogue no-such-session /nowhere "$TMP_ROOT/o10.md"
assert_eq 1 "$OUT_STATUS"
[ -e "$TMP_ROOT/o10.md" ] && fail "out-file written although not found"
dialogue only-one-arg
assert_eq 2 "$OUT_STATUS"
dialogue --help
assert_eq 0 "$OUT_STATUS"
help="$(cat "$TMP_ROOT/stdout")"
for w in "<session-id>" "<project-path>" "<out-file>" "0  written" "1  transcript not found" "2  usage error"; do
  assert_contains "$help" "$w"
done
