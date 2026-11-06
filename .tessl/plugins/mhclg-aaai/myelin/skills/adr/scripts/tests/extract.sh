#!/usr/bin/env bash
# What the adapter keeps and what it drops. Sourced by run.sh after lib.sh.

P=/work/proj

t "1. a human message as a string and as text blocks become ### Human, verbatim"
place human "$P"; dialogue sess-1 "$P" "$TMP_ROOT/o1.md"
out="$(cat "$TMP_ROOT/o1.md" 2>/dev/null)"
assert_eq 0 "$OUT_STATUS"
assert_contains "$out" $'### Human\n\nFirst message, typed as a string.'
assert_contains "$out" $'### Human\n\nSecond message,\nas text blocks.'

t "2. assistant text becomes ### Assistant; thinking and tool calls are dropped"
place assistant "$P"; dialogue sess-1 "$P" "$TMP_ROOT/o2.md"
out="$(cat "$TMP_ROOT/o2.md" 2>/dev/null)"
assert_eq 0 "$OUT_STATUS"
assert_contains "$out" $'### Assistant\n\nHere is my answer.'
assert_not_contains "$out" "SECRET-REASONING"
assert_not_contains "$out" "TOOL-CALL-TEXT"

t "3. tool results are dropped, except a question's answer"
place tools "$P"; dialogue sess-1 "$P" "$TMP_ROOT/o3.md"
out="$(cat "$TMP_ROOT/o3.md" 2>/dev/null)"
assert_eq 0 "$OUT_STATUS"
assert_not_contains "$out" "TOOL-OUTPUT-STRING"
assert_not_contains "$out" "TOOL-OUTPUT-ARRAY"
assert_contains "$out" $'### Answer\n\nThe user answered: "Pick one?"="A"'

t "4. sidechain entries are dropped"
place sidechain "$P"; dialogue sess-1 "$P" "$TMP_ROOT/o4.md"
out="$(cat "$TMP_ROOT/o4.md" 2>/dev/null)"
assert_eq 0 "$OUT_STATUS"
assert_not_contains "$out" "SIDECHAIN"
assert_contains "$out" $'### Human\n\nMain thread.'

t "5. harness-injected entries are dropped"
place injected "$P"; dialogue sess-1 "$P" "$TMP_ROOT/o5.md"
out="$(cat "$TMP_ROOT/o5.md" 2>/dev/null)"
assert_eq 0 "$OUT_STATUS"
for s in META-HANDBACK ANGLE-INJECTED ANGLE-BLOCK ATTACHMENT-REMINDER QUEUED-NOTIFICATION QUEUE-OP SYSTEM-ENTRY; do
  assert_not_contains "$out" "$s"
done
assert_contains "$out" $'### Human\n\nKept.'

t "6. a question becomes ### Question with its options, its answer the ### Answer after it"
place tools "$P"; dialogue sess-1 "$P" "$TMP_ROOT/o6.md"
out="$(cat "$TMP_ROOT/o6.md" 2>/dev/null)"
assert_eq 0 "$OUT_STATUS"
assert_contains "$out" $'### Question\n\nPick one?\n- A: the first\n- B: the second\n\n### Answer\n\nThe user answered: "Pick one?"="A"'

t "7. order is preserved, byte for byte, across a mixed transcript"
place mixed "$P"; dialogue sess-1 "$P" "$TMP_ROOT/o7.md"
assert_eq 0 "$OUT_STATUS"
if ! cmp -s "$FIXTURES/mixed.expected.md" "$TMP_ROOT/o7.md"; then
  fail "output differs from fixtures/mixed.expected.md: $(diff "$FIXTURES/mixed.expected.md" "$TMP_ROOT/o7.md" 2>&1 | head -5)"
fi

t "11. a message the human sent while a turn ran becomes ### Human, in order"
place queued "$P"; dialogue sess-1 "$P" "$TMP_ROOT/o11.md"
out="$(cat "$TMP_ROOT/o11.md" 2>/dev/null)"
assert_eq 0 "$OUT_STATUS"
assert_contains "$out" $'### Assistant\n\nWorking on it.\n\n### Human\n\nSent while you were working.\n\n### Assistant\n\nNoted.'
