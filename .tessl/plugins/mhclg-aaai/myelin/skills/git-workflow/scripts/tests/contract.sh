# The usage text is the contract: it names the subcommands, the host
# module interface and the exit codes, and unknown input is a usage error.
t "usage text is the contract"
  out="$(bash "$SCRIPT" --help 2>&1)"; code=$?
  assert_eq 0 "$code" "--help should exit 0"
  for word in check begin land hosts/; do assert_contains "$out" "$word"; done
  for code_line in "0 " "1 " "2 " "3 "; do assert_contains "$out" "$code_line"; done
  assert_exit 2 bash "$SCRIPT"
  assert_exit 2 bash "$SCRIPT" frobnicate
