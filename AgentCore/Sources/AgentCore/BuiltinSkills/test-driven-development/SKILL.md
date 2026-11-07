---
name: test-driven-development
description: Use when asked to work test-first or TDD, red-green-refactor, or to fix a bug by first writing a test that reproduces it. Each behavior proven by a test seen failing. Not for tests of existing code (write-tests).
---

# Test-driven development

Grow the code one behavior at a time: a test that fails for the right reason, the least code that passes it, then a
cleanup with every test still green.

## Fast path

A one-line bug fix or a tiny function: one test that reproduces the bug or states the behavior, run it and see it
fail, make the change, see it pass, run the whole suite. The failing run is never optional, even here.

## Steps

1. **List the behaviors.** From the request, issue or spec, write a checklist with one line per behavior: each
   example, each rule, each error case. Order it simplest first, then edge cases, then errors.

2. **Red.** Write one test for the next unchecked behavior, using only the public interface the request names.
   Run that test alone (commands below). It must fail, and for the reason you expect: a wrong value or a missing
   function. A syntax error, an import typo or a broken fixture is not a red; fix the test and rerun.
   If it passes before you wrote any code, either the behavior already exists (check it off) or the test does not
   reach the code you think it does (fix the test).

3. **Green.** Write the least code that makes this test pass. Run it, then the whole test file. Don't add code for
   behaviors further down the list; their tests come first.

4. **Refactor.** Remove duplication, improve names, simplify. Run the tests after each change. Refactoring adds no
   behavior; if you want new behavior, it needs a new red test.

5. **Repeat** until the checklist is done. Choose inputs that tell a right implementation from plausible wrong ones:
   a case where the "largest" item is not the first one, a tie, a value exactly on a limit, an empty input.
   Ask of each test: "which wrong implementation would pass this?" If one obviously would, add a sharper case.

6. **Finish with the whole suite**, using the project's full test command (look in CI config, `Makefile`,
   `package.json`), not only your new file. Name every failing test in the report, including any that already
   failed before you started.

Running one test:

| Stack | Command |
|---|---|
| Python | `python3 -m unittest tests.test_x.Case.test_y`, `pytest tests/test_x.py -k name` |
| JS/TS | `npx jest -t "name"`, `npx vitest run -t "name"`, `node --test --test-name-pattern="name"` |
| Go | `go test -run 'TestName' ./pkg/...` |
| Rust | `cargo test name` |
| Swift | `swift test --filter Suite/testName` |
| Java | `mvn -Dtest=Class#method test`, `gradle test --tests Class.method` |

**Bug fixes:** the first test reproduces the reported symptom. Watch it fail with that symptom, then fix the cause.
**Code with no tests around it:** before changing existing behavior, pin what it does now with a few tests that pass
on the current code, then drive the new behavior test-first (larger restructuring belongs to refactor-safely).
**Where test-first is awkward** (visual UI, exploratory spikes, generated code): test the logic under the view and
check the view by running it; throw spike code away and redo it test-first; test the generator, not its output.
Say in the report which parts were not test-driven.

## Rules

- **Don't** write the implementation first and the tests after. Tests written to fit existing code assert what it
  does, bugs included. If code came first, set it aside (stash or comment it out), write the test, see it fail,
  then bring the code back.
- **Don't** count a test you never saw fail as evidence. It may not test anything.
- **Don't** change a test's expected value to match the code. Change it only when the requirement shows the test
  was wrong, and say so.
- **Don't** test private helpers when the request names a public interface: those tests break on every refactor
  and miss what callers see.
- **Don't** mock the unit under test. Fake only slow or outside things (network, clock, randomness).

## When no one can answer

If a requirement is ambiguous, pick the reading the given examples support, pin it with a test whose name or
comment says `assumption:`, list it in the report and continue. If the examples contradict the rules, follow the
rules and report the contradiction. Stop only if the tests cannot be run at all.

## Done means

- The tests and the implementation, with every test passing.
- A short red/green log: per behavior, the test name and the one-line failure you saw before the code existed.
- The full-suite command and its result (counts), and any test that fails, by name.
- Assumptions made, and parts not driven by tests.
