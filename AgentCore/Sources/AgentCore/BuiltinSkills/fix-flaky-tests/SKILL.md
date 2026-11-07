---
name: fix-flaky-tests
description: Use when a test passes on some runs and fails on others, fails only in CI, only with other tests, in some orders or at some times. Proves the flake, finds the cause, fixes it. Not for tests that always fail (systematic-debugging).
---

# Fix a flaky test

Find why a test's result changes between runs and fix that cause, so the test is reliable without being weakened.

## Fast path

If the cause is visible on reading (a `sleep` before an assertion, an unseeded random value, a test that edits shared
state without restoring it), still prove it with step 1 before and step 5 after the fix. Never skip the proof.

## Steps

1. **Prove the flake and measure it.** Run the test many times and count failures:
   `python3 <skill folder>/scripts/repeat.py -n 30 -- <command that runs the test>`
   Then the same three ways: the test alone, its whole file, the whole suite. Use the project's own runner and its
   random-order or parallel options if CI uses them (look in CI config, `Makefile`, `package.json`, `tools/`).
   Save the failing output. If it never fails in 30 runs anywhere, say so and look at CI's environment (step 2, "only
   in CI") before changing code.

2. **Classify by where it fails.**
   - Fails **alone** sometimes: timing (sleeps, timeouts, async not awaited), randomness, the clock (dates, time
     zones, midnight), unordered data (set/dict/directory order), ports or files that may be taken.
   - Fails **only with other tests** or in some orders: shared state another test leaves behind. Find the polluter:
     `python3 <skill folder>/scripts/find_polluter.py --run '<runner that takes test ids in order>' --target <id> --candidates <file with one test id per line>`
     It bisects the tests that run before the target and prints the one that breaks it.
   - Fails **only in CI**: environment (locale, time zone, CPU count, parallel workers, missing services, file system
     case), or slower machines exposing timing.

3. **Find the cause in code, not in the symptom.** Read the polluter or the timing-dependent code. Typical causes:
   module-level caches or singletons mutated by a test; a returned shared object modified in place; global config,
   environment variables or the working directory changed and not restored; mocks not undone; leftover files or
   database rows; threads still running when the test ends.

4. **Fix the cause.** Prefer, in order: make the code under test not share mutable state (return copies, inject
   dependencies); make the test set up and tear down its own state (fresh objects, temp dirs, `addCleanup`, fixtures
   with teardown); replace sleeps with waiting on the condition (poll with a deadline); seed randomness and freeze or
   inject the clock; sort before comparing unordered data; ask the OS for a free port.

5. **Prove the fix.** Repeat step 1 with the same commands and at least as many runs (30, or ten times the inverse of
   the failure rate you measured), in random order if CI uses it, then run the whole suite once more.

## Rules

- **Don't** skip, mark expected-to-fail, quarantine, add retries, or raise timeouts as the fix: each hides the bug and
  the next flake in the same place. Only do it if the user asks, and say what remains broken.
- **Don't** delete or loosen assertions to make the result stable. The assertion is usually right; the setup isn't.
- **Don't** declare it fixed from a single passing run. A flake that fails one time in five passes a single run 80% of
  the time.
- Fix the polluter, not only the victim: resetting state in the failing test leaves the next test exposed.

## When no one can answer

Choose the fix that removes shared state with the smallest change to production code, note the choice and its
alternative in your report, and continue. Stop and report instead only if the fix needs a change to CI or
infrastructure you can't make, or if the flake can't be reproduced and no cause is visible in the code.

## Done means

A short report with: **cause** (file:line, one sentence), **class** (timing, order/shared state, environment),
**fix** (what changed and why it removes the cause), and **evidence**: the repeat command and the counts before
(e.g. "9/30 failed") and after ("0/30"), plus the full-suite result.
