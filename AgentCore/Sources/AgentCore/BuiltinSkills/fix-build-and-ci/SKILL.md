---
name: fix-build-and-ci
description: Use when a build, compile, lint, type check or CI job fails (a red pipeline or PR check, a broken make, npm, cargo, gradle or Xcode build). Finds the first real error and fixes its cause. Not for flaky tests (fix-flaky-tests).
---

# Fix a failing build or CI run

Make the failing step pass by fixing what is actually wrong, with every check still as strict as before.

## Fast path

If the failure is one clear error in code you can see (a typo, a missing import, a type mismatch), fix it, run the
failing step and then the whole pipeline locally, and report. Still read the error in full and keep the Rules.

If you were only asked to run something and say what failed, do steps 1 and 2 and report the first real error
(quoted, with file:line) and any separate causes; change nothing.

## Steps

1. **Get the log and the exact command.** Locally: run the failing command so that you both see its output and keep
   it (`set -o pipefail; <cmd> 2>&1 | tee build.log`). Don't send it only to a file you then don't read: read the
   output you got, and `build.log` for what it left out. In CI: take the failed job's log (a saved file, or
   `gh run view <run-id> --log-failed` if the GitHub CLI is installed). Find the step that failed and the command it runs in the CI config
   (`.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, `Makefile`, `package.json` scripts, `ci.sh`).

2. **Find the first real error.** Run
   `python3 <skill folder>/scripts/first_error.py build.log`
   and read the `FIRST` block. Logs usually end with consequences, not the cause:
   - `WRAPPER` lines ("exit code 1", "make: *** Error 2", "step failed", "BUILD FAILED") are never the cause.
   - One cause often produces many later errors: a failed code-generation or data step makes later imports or
     lookups fail; one compile error produces dozens. Fix the earliest one, re-run, then look again.
   - Several `ALSO` lines in different steps or files may be separate causes. List them and handle each in order.
   Confirm the script's pick by reading the context it prints.

3. **Reproduce locally** with the same command, from a clean state, before changing anything: install from the
   lockfile and remove build outputs (commands per stack: `references/ecosystems.md`). Run the steps in CI's order,
   because an earlier step may generate what a later one needs. If it does not reproduce, compare tool versions,
   environment variables, OS and file-system case, and files present locally but not committed
   (`git status --ignored`). The reference file lists the usual CI-only causes.

4. **Find the cause.** Read the code or file the error points at, and the recent change that touched it
   (`git log -p -3 -- <file>`). Ask what the check is telling you:
   - A lint or type finding is often a real bug. An unused variable usually means a computed value is never used;
     "possibly undefined" means a path where it is.
   - A data, config or schema error: fix the input, not the validator that rejected it.
   - A dependency or toolchain error: compare the lockfile and versions with the last green run.

5. **Fix one cause at a time.** Make the smallest change that removes it and re-run the failing step after each fix.

6. **Run the whole pipeline locally** (every step, in order, from a clean state) and confirm it exits 0. If the
   failure only happens in CI, say what you could not reproduce and what evidence you have instead.

## Rules

- **Don't weaken a check to make it pass.** No ignore comments (`# noqa`, `# type: ignore`, `// eslint-disable`,
  `@ts-ignore`, `#[allow]`, `@SuppressWarnings`), no disabled rules or raised thresholds in config, no `|| true`,
  `continue-on-error` or removed steps, no skipped, deleted or narrowed tests, no loosened validators. "It's only
  lint" is the excuse this blocks: the check was right more often than not. Do it only if the user asks, and say
  what it now hides.
- **Don't delete the flagged code to quiet a finding.** Removing an "unused" variable or import silences the
  warning and keeps the bug if the value should have been used. Read the whole function first.
- **Don't change a test's expected value** to match new output unless the behavior change was intended and you can
  say why it is correct.
- **Don't start from the last lines of the log.** They show the step that gave up, not why.
- **Don't commit generated files** (build output, compiled tables, lockfiles from a different tool version) to get
  past a step that is supposed to produce them.
- **Don't push or re-run CI to "see if it passes"** before it passes locally; each round trip hides what changed.

## When no one can answer

If you can't get the CI log, reproduce with the commands from the CI config and say so. If a check looks wrong for
this codebase (a rule that misfires, a test asserting old behavior), fix the code if you can do it honestly;
otherwise leave the check alone, record it under "needs a decision" in your report, and finish the other causes.
Don't push, merge or re-run CI unless the request said to. Stop only if the cause is outside the repository (a
secret, a runner, a service you can't reach): report the first error and what would fix it.

## Done means

A short report with:
- **failing step** and its command;
- **first real error** quoted, with file:line, and any separate causes found after it;
- **cause** in one sentence per error, and **fix** (what changed and why it removes the cause);
- **evidence**: the full pipeline command run locally from a clean state and its exit status;
- **not verified**: anything that depends on the CI environment you could not reproduce.
