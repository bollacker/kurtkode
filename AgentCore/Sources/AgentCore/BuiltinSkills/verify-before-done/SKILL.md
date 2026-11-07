---
name: verify-before-done
description: Use when about to say work is done, fixed or passing, or when asked to double-check, confirm or prove a change works. Fresh evidence per claim, a not-verified list. Not for reviewing someone else's diff (code-review).
---

# Verify before saying done

Every claim of "done", "fixed" or "passing" rests on output you saw in this session after your last edit, and
everything you could not check is listed as not verified.

## Fast path

A small change in a project with one obvious test command: find what CI runs (step 2), run it after your last
edit, read the counts and exit code, check the original request once by hand, and report both with a not-verified
line. That is the whole skill for small work; don't skip step 2, it is where the surprises are.

## Steps

1. **List the claims you are about to make**: "the bug is fixed", "the feature works", "nothing else broke". Each
   claim needs its own evidence (table below).

2. **Find the project's full check.** CI decides what "passes" means, not the default test command:
   `python3 <skill folder>/scripts/find_checks.py`
   It prints the CI steps, Makefile/justfile targets, package.json scripts and build-tool checks (`CI`, `MAKE`,
   `NPM`, `BUILD`, `SCRIPT` lines), then every test folder (`TESTDIR`), flagging folders that default discovery
   skips. Exit 1 means nothing was found: read README/CONTRIBUTING and run each test folder yourself.
   Run all of it: every test folder, lint, type check, build.

3. **Run it fresh, after your last edit.** Not an earlier run, not a teammate's or subagent's report. Read the
   exit code and the counts, not just the last line: a runner that collected 0 tests also prints "OK". Check the
   number of tests run is what you expect.

4. **Check the request itself, not only the tests.** Run the example from the request, rerun the original
   reproduction, call the CLI, load the page. For a bug fix, prove the regression test can fail: stash or revert the
   fix, run the test, see it fail, restore the fix, see it pass.

5. **Read your own diff**: `git status` and `git diff` (plus new untracked files). Every change is intended; no
   debug output, stray files, or test edits that loosen an assertion.

6. **If anything fails, it is not done.** Fix it and go back to step 3. To call a failure pre-existing, run the
   same command on the base commit (`git stash`, run, `git stash pop`, or a worktree) and quote both results.
   When the failing test is not one you wrote, read its name, docstring and the code it calls: it states a
   requirement (a file format, another consumer, an old client). Fix the code so your change and that requirement
   both hold, for example by converting at the boundary that test covers. Editing that test or its docstring to
   pass is not a fix; it hides a break that someone else will hit.

| Claim | Evidence it needs |
|---|---|
| tests pass | the full check's command and output (counts, exit 0), run after the last edit |
| bug fixed | the original symptom gone when rerun; the regression test seen failing without the fix |
| feature works | each acceptance point checked by a test or by running it, one line each |
| builds / types are fine | the compiler or type checker's output; a linter is not a compiler |
| nothing else broke | everything CI runs, not only the tests next to the change |
| an agent or tool did X | the diff or file inspected by you |
| UI looks right | the app run and looked at (screenshot), or listed as not verified |
| deployed service works | a real request against it, or listed as not verified |

## Rules

- **Don't** report "should work", "probably fine" or "looks right". Run the check, or put the item under
  Not verified.
- **Don't** reuse a result from before your last edit, however small the edit was.
- **Don't** shrink the run to the file you touched and call it the suite. Breakage shows up far from the change.
- **Don't** edit, skip or delete a failing test to get green. A test your change breaks usually guards a different
  requirement (another consumer, a file format, an old client) that the request didn't touch: keep that test as it
  is and change your code at the boundary so both hold. Edit a test only when the request itself names the behavior
  it checks, and say so in the report.
- **Don't** call a failure flaky or pre-existing without running it on the base commit.

## When no one can answer

If a check cannot run here (needs network, credentials, a device, a paid service), don't wait for permission and
don't pretend: run everything else, then list the missing check with the exact command someone should run. Report
the work as "done except the checks listed", never as plain "done". A failure you can't fix in scope is reported
with its output, not hidden.

## Done means

A report (in the file the user asked for, else in your reply) with these parts:

- **Changed**: one line per change.
- **Verified**: each command you ran after the last edit and its result (counts, exit code), plus the manual checks.
- **Not verified**: what, why, and the command to run it.
- **Failures**: any red check by name, with evidence whether it predates your change.
