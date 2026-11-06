# The dialogue format

The summariser reads one file in this format, whichever mode produced
it: the harness adapter or the parent's fallback.

- The file is Markdown. Line 1 is `# Dialogue`. Line 2 is exactly one
  of `Mode: adapter (claude-code)` or `Mode: fallback`.
- Then, in conversation order, one block per turn. Each block opens
  with a level-3 heading on its own line, `### Human`,
  `### Assistant`, `### Question` or `### Answer`, followed by that
  turn's text verbatim.
- `### Human` is a message the human typed. `### Assistant` is
  assistant prose shown to the human. `### Question` is a question the
  assistant put to the human through a question tool, with its options
  one per line as `- <label>: <description>`. `### Answer` is the
  human's answer to the question block before it.
- Left out: tool calls and tool output, reasoning, subagent
  conversations, and messages the harness injected rather than the
  human typed.
- The file is written outside the repository, in the session's
  temporary directory, and is never committed.
