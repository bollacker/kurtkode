---
name: bisect-regression
description: Use when something worked in an older version, tag or commit and is broken now, and you need the commit that broke it ("which commit", git bisect). Finds it by test. Not for bugs never known to work (systematic-debugging).
---

# Find the commit that broke it

Let a test, not commit messages, pick the first bad commit between a known-good and a known-bad revision.

## Fast path

If the range is a handful of commits, you may test them one by one instead of bisecting. The proof is the same
either way: the test passes at `<sha>^` and fails at `<sha>`. Never name a commit without that pair.

## Steps

1. **Pin the endpoints.** Bad is usually `HEAD`. Good is the tag, release or date the user named
   (`git rev-list -1 --before=2026-03-01 main` for a date). If none is known, try older tags
   (`git tag --sort=creatordate`) until the behavior is right; if it was never right, this is not a regression.

2. **Write the test script outside the working tree** (e.g. `/tmp/bisect-test.sh`): every checkout rewrites tracked
   files, and a test file added after the good commit doesn't exist there. Exit codes decide each commit:
   `0` good, `1` bad, `125` can't test this commit (skip). Template:

   ```sh
   #!/bin/sh
   cd "$(git rev-parse --show-toplevel)"
   make build >/dev/null 2>&1 || exit 125          # can't build: skip, not bad
   out=$(./app export orders.db 2>&1) || exit 125    # crashes for another reason: skip
   echo "$out" | grep -ci '^order id' | grep -qx 1   # the one behavior in question
   ```

   - Test **only the behavior in question.** Normalize output that changed on purpose in the range (formatting,
     ordering, extra lines, renamed flags); otherwise the search finds that intended change instead.
   - Build or import failures, missing files and unrelated crashes are **125**. If the regression itself is a crash,
     match its message (`grep -q 'KeyError: .region.'`) so other crashes still skip.
   - Bound hangs: wrap the run in a timeout and decide whether a hang is the bug (bad) or noise (skip).
   - Build commands by stack: `pip install -e . -q`, `npm ci && npm run build`, `go build ./...`, `cargo build`,
     `swift build`, `mvn -q -DskipTests package`. Dependency installs per commit are slow; skip them when the
     lockfile didn't change.

3. **Run the bundled bisect script** from the repository:

   ```
   python3 <skill folder>/scripts/bisect_run.py --good <rev> [--bad HEAD] [--build '<cmd>'] -- sh /tmp/bisect-test.sh
   ```

   It refuses a dirty tree or a running bisect, checks that the test passes at good and fails at bad, runs
   `git bisect run` with skips, and always resets to the starting branch. Read its output:
   - `FIRST_BAD <hash> <subject>` (exit 0): the answer, go to step 4.
   - `ENDPOINT good|bad … WRONG` (exit 1): the test is wrong or the good revision isn't good. Run the test by hand
     at that revision (`git checkout --detach <rev>`, run, `git checkout -`), fix the test, rerun.
   - `AMBIGUOUS` lines (exit 1): only skipped commits separate good from bad. Make the test work on them (often a
     build fix you can apply inside the script) or report the candidate range and read their diffs.
   - `STEP` lines show every decision; many skips mean the test or build is fragile.

   Without the script: `git bisect start <bad> <good>`, `git bisect run sh /tmp/bisect-test.sh`, then always
   `git bisect reset`.

4. **Confirm and explain.** Run the test at `<sha>^` (passes) and `<sha>` (fails). Read `git show <sha>` and name
   the hunk that causes it. If the first bad commit is a merge, bisect the merged branch's own commits next.

## Rules

- **Don't** pick the culprit from commit messages or `git log -p` reading alone. A "Fix rounding" commit is often
  innocent; the test decides.
- **Don't** let a test failure that isn't the symptom count as bad. Unbuildable commits marked bad send the search to
  the first broken commit, not the regression.
- **Don't** leave the repository mid-bisect or detached; finish with `git bisect reset`. Don't commit, stash, rebase
  or edit tracked files during a bisect.
- Don't fix the bug as part of the search unless asked; report first. If a fix is wanted, make it after the reset,
  on the branch.

## When no one can answer

Pick the good revision yourself (the user's version, else the newest tag where the test passes) and say which. If the
behavior can't be scripted, bisect by hand with `git bisect good|bad|skip` and record each verdict. Stop and report
only if no revision in history passes the test (not a regression) or the candidates stay ambiguous after one attempt
to make them testable.

## Done means

- The **first bad commit**: full hash, subject, author, date, and the hunk that causes the change; written to the
  file the user named, if any.
- The **test script** (its content) and the **evidence**: passes at `<sha>^`, fails at `<sha>`, and the number of
  commits tested and skipped.
- The repository back on its original branch with no bisect in progress.
