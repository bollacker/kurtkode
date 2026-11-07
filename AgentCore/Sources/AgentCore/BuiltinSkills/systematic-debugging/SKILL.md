---
name: systematic-debugging
description: Use when chasing a bug, crash, stack trace, wrong output or failing test whose cause is unknown. Finds the root cause, fixes it there, proves it. Not for intermittent failures (fix-flaky-tests) or regressions (bisect-regression).
---

# Debug to the root cause

Find where a correct input first becomes a wrong value, fix it there, and prove the fix with a test.

## Fast path

If the error names both the cause and the place (a typo, a missing import, a wrong argument on the line the trace
shows) and the fix is one line: fix it, run the failing test, then the whole suite. If that first fix doesn't work,
leave the fast path and start at step 1.

## Steps

1. **Reproduce.** Run the exact failing command and keep its output. No reproduction yet: write the smallest script
   or test that shows the failure. If it fails only sometimes, use fix-flaky-tests; if it worked in a known older
   version, bisect-regression may find the cause faster.

2. **Read the whole error.** Every frame of the trace, the first error in the log (not the last), chained causes
   ("Caused by", "During handling of the above exception"). For trace formats per language, logs, core dumps and
   driving gdb/lldb/pdb without an interactive session, read `references/diagnostics.md`.

3. **Trace the bad value upstream.** At the failure site, find which value is wrong (print it with `repr()` /
   `JSON.stringify` / `%#v` so hidden characters show, or use a debugger). Then find where that value came from and
   check it there. Repeat until you reach the code where good input turns into bad output: that is the root cause.
   In a system with several layers, log the input and output of each layer in one run instead of guessing layer by
   layer.

4. **Test one hypothesis at a time.** Write it down ("the cache key leaves out the locale, so the second user gets the first user's prices"),
   predict what an experiment will show, run it. Then capture the cause as a failing test at the cause's level (a
   unit test of the module where the bug lives), not only at the symptom.

5. **Fix at the cause.** Make the smallest change there. Then find the other callers of what you changed
   (`grep -rn <name>`) and confirm they still work, and look for the same mistake elsewhere.

6. **Prove it.** The new test passes, the originally failing test passes, the full suite passes. Remove debug prints
   and temporary logging.

**Three failed fixes means stop patching.** Your model of the problem is wrong. Go back to step 3 with new
instrumentation, and question the design (shared state, wrong layer owning the logic) before trying a fourth fix.

## Rules

- **Don't** fix where the symptom shows just because the trace points there. A guard, default, `strip()`, `try/except`
  or special case at the crash site hides the cause from every other caller. Add a check at the symptom only in
  addition to the real fix.
- **Don't** change several things at once; when the test passes you won't know which change mattered.
- **Don't** edit a test's expected value or its data to make it pass unless you've shown the test is wrong, and then
  say so in the report.
- **Don't** report a cause you haven't confirmed by an experiment. Unconfirmed ideas are hypotheses; label them.
- **Don't** catch and ignore the exception to make the crash go away (see error-handling).

## When no one can answer

Make the fix at the root cause even if it touches a module the user didn't mention, and list every caller you
checked. If the right behavior is unclear (is the input invalid or the code wrong?), choose the behavior the existing
tests and docs imply, record it as an assumption, and continue. Stop and report instead after three failed fixes, or
when the cause is outside the repository (a dependency bug, the environment, the data source), with the evidence and
a proposed workaround.

## Done means

A short report with:
- **Symptom**: the failing command and its error.
- **Root cause**: file:line, the mechanism, and why it produced the symptom.
- **Fix**: what changed and why it fixes the cause rather than the symptom; other callers checked.
- **Evidence**: the new test's name, and the commands with results before (failing) and after (passing), including
  the full suite.
- If stopped: each attempt, what it showed, and what to try next.
