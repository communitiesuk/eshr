---
name: test-first-workflow
description: The mandatory workflow for writing code in any project the user works in. TRIGGER on any task that involves writing or modifying executable code (new functions, refactors, bug fixes, added features). SKIP for pure config edits, doc-only changes, exploratory reads. Enforces docstrings first, then failing tests, then code. The tests are the contract.
---

# Test-first workflow

Use this whenever you're about to write or modify executable code. It is the user's standing rule for how coding gets done. The four phases below are mandatory and ordered — do not skip, do not merge, do not reorder.

## Phase 1 — Docstrings first

Before writing any executable logic:

- **For new functions**: write the function signature and a docstring describing purpose, parameters, return value, raised exceptions, and side effects. The body is `raise NotImplementedError` or `...` — nothing more.
- **For modified functions**: update the docstring to describe the new behaviour *before* you touch the body. If the docstring doesn't change, the behaviour probably doesn't either — challenge the task.
- **For module-level docstrings**: update lists of env vars, exported names, or module purpose so they reflect the target state.

Commit the docstring changes on their own if the scope is non-trivial. The point: force yourself to specify the contract in prose before writing tests or code.

## Phase 2 — Tests next, and they must fail

Write tests against the docstrings. Tests are the executable contract; the code will be judged against them.

- Run the new tests **before** writing implementation. Confirm every new test fails for the right reason (the feature is missing, not an import error or a typo). If any test passes accidentally, it's testing the wrong thing — fix the test.
- Cover the happy path, each documented failure mode, and boundary conditions (empty, whitespace, missing env vars, partial config, unicode where relevant).
- **If secrets are involved** (API keys, tokens, client secrets, passwords, PII), you must add explicit assertions that the secret does not leak:
  - Not present in any raised exception's `str(exc)` or `repr(exc)`.
  - Not present in captured logs (`caplog`).
  - Not present in any subprocess command line (`argv`) if a subprocess is invoked.
  - Not written to any file the code creates.
- Review each test against this checklist before proceeding to code:
  1. Would a plausible-but-wrong implementation still pass this test? If yes, tighten the assertion.
  2. Does the test exercise a failure path, or only the happy path?
  3. If secrets are in play, is there an explicit non-leak assertion?
  4. Are env-var / global mutations properly isolated (`monkeypatch`, fixtures)?

Commit the tests on their own (a red commit). This makes the contract auditable in git history.

## Phase 3 — Code last

Write the minimum code that turns every test green.

- Do not modify a test to make it pass. **The tests are the contract**: if a test fails, the code is wrong.
- The only exception: you can prove a specific test is invalid (e.g. it asserts an impossible or contradictory condition, or it was written against a misunderstood spec). If you edit a test after this point, state the reason explicitly in the commit message.
- Run the full suite, not just new tests — you may have broken something adjacent.
- If the code passes tests but feels wrong, add a test that captures the wrongness, then fix. Do not "fix" silently.

Commit the code on its own (a green commit).

## Phase 4 — Verify beyond unit tests

- Run linters/type-checkers.
- For UI or feature work, exercise the feature end-to-end in the running app (or explicitly say you couldn't).
- For anything touching auth, storage, or external calls, run a smoke test against a real dependency where possible.

## When you may deviate

- Trivial changes (typo fix, one-line rename, obvious dead-code removal): skip Phase 1 and 2, go straight to code. State that you're skipping and why.
- Pure exploration / reading code: this skill doesn't apply.
- The user explicitly says "just write the code" or "no tests needed": follow their instruction, but note the deviation in your reply.

## Anti-patterns to avoid

- Writing code and tests in the same commit (the contract wasn't red first — you're testing what you wrote, not what you specified).
- Editing a test to make a failing implementation pass without explicit justification.
- Adding tests only for the happy path.
- Assertions loose enough that any string / non-None value passes ("assert result" instead of "assert result == expected").
- Trusting that a secret won't leak because "it doesn't now" — add the assertion so the invariant is enforced.
