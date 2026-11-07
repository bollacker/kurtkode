---
name: write-tests
description: Use when code has no tests or weak ones, or when asked to add unit tests, raise coverage or find untested risk. Tests that catch real bugs. Not for test-first work (test-driven-development) or flaky tests (fix-flaky-tests).
---

# Write tests that catch bugs

Add tests that fail when the code breaks, aimed at the rules and boundaries where bugs live, not at a coverage number.

## Fast path

One small function with a clear contract: list its rules, test each boundary on both sides plus one invalid input,
run the tests, then break one line of the code on purpose and watch a test fail. Restore the line.

## Steps

1. **Write down the contract before any test.** Read docstrings, comments, README, type signatures, the callers and
   any issue text. List every rule as one line: input classes, limits ("at most 30 days"), error cases, ordering,
   side effects, what is returned for empty or zero. This list is your test plan.

2. **Rank what to test by risk** when there is more code than time: parsing and validation, money, dates and time,
   permissions, error paths, branches with several conditions, code that changed recently or broke before. Skip
   trivial getters and pass-through wrappers. To find untested code, run coverage and read the uncovered lines:
   - Python: `python3 -m coverage run -m pytest && python3 -m coverage report -m` (or `-m unittest`)
   - JS/TS: `npx jest --coverage`, `npx vitest run --coverage`, `node --test --experimental-test-coverage`
   - Go: `go test -coverprofile=c.out ./... && go tool cover -func=c.out`
   - Rust: `cargo llvm-cov` if installed; Swift: `swift test --enable-code-coverage`; Java: JaCoCo via Maven/Gradle
   Treat the percentage as a map of where to look, not a target.

3. **Use the project's framework, layout and naming.** Find an existing test file and copy its style. If none exists,
   use the language's standard tool (unittest/pytest, `node:test`/Jest/Vitest, `go test`, `cargo test`, XCTest).

4. **Write one test per rule**, named after the rule (`test_exactly_30_days_is_allowed`). For each rule cover:
   - both sides of every boundary: at the limit and one step past it (0 and -1, max and max+1);
   - empty, one, many; blank strings; duplicates; wrong order;
   - each documented error, checking the error type (and message if the contract names it);
   - invariants where they exist: round trips (`parse(format(x)) == x`), totals that must add up, sort stability.
   Assert exact values. A test that only checks "no exception" or "is not None" catches almost nothing.

5. **Run the new tests.** All must pass. When one fails, decide which side is wrong by the contract from step 1,
   not by which is easier to change (see Rules).

6. **Prove the tests can fail.** Run the mutation helper on each file under test:
   `python3 <skill folder>/scripts/mutate.py --file <source file> -- <command that runs the tests>`
   It flips comparisons, swaps and/or, nudges constants and drops `strip()` or `raise` lines one at a time, and prints
   each change no test noticed (`SURVIVED file:line: old -> new`). For every survivor, add the missing test or note
   why the change can't matter (an equivalent mutant, e.g. `x <= lo` where both branches return `lo`). Rerun until
   only equivalent mutants survive. Exit 0 = all killed, 1 = survivors listed, 2 = tests failed before mutating.
   Without the helper: break each key line by hand, run, confirm a failure, restore, and check `git diff` is clean.
   Real mutation tools, if installed, do the same at scale: mutmut, Stryker, cargo-mutants, PIT.

7. **Run the whole suite once** with the project's full test command, so the new tests don't clash with old ones.

## Rules

- **Don't** copy the current output into an assertion without checking it against the contract: that freezes bugs
  in place. If code and contract disagree, write the test for the contract and report the bug.
- **Don't** edit the code under test to make your tests pass unless asked. If you find a bug, keep the test that
  shows it (marked as a known failure: `@unittest.expectedFailure`, `pytest.mark.xfail(strict=True)`,
  `test.failing`) and name it in the report.
- **Don't** mock the unit you are testing or its pure helpers. Mock only slow or outside things: network, clock,
  randomness, other services. A test of a mock tests nothing.
- **Don't** pad coverage with tests that execute lines without asserting results. They make the number lie.
- Keep tests independent: no shared mutable state, no order dependence, no real sleeps or network.

## When no one can answer

If the contract is unclear, rank the sources: written docs and types, then what callers rely on, then current
behavior. Tests based only on current behavior get a comment saying so ("pins current behavior; unconfirmed").
Record each assumption in the report and continue. Stop only if you can't run the tests at all.

## Done means

- Test files in the project's layout, passing with the project's test command (show the command and its result).
- Mutation evidence: the helper's `RESULT killed=K survived=S` line, with each remaining survivor explained, or the
  list of lines you broke by hand and the test that caught each.
- A short report: rules covered, rules deliberately left untested and why, bugs found (with the failing test name),
  and assumptions made.
