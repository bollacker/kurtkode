---
name: resolve-merge-conflicts
description: Use when git reports CONFLICT in a merge, rebase, cherry-pick or stash pop, files contain <<<<<<< markers, or a branch can't merge cleanly. Keeps both sides' intent, proven by tests. Not for committing work (commit-and-pr).
---

# Resolve merge conflicts

Finish a conflicted merge, rebase or cherry-pick so the result does what both sides meant, not what one side wrote.

## Fast path

One small hunk where one side only changed whitespace, comments or an import order, or both sides made the same
change: resolve it, run the step 6 checks and the tests, continue. Anything that touches logic, names, signatures
or units gets the full steps.

## Steps

1. **See what is in progress.** `git status` names the operation and the conflicted paths. Then run
   `python3 <skill folder>/scripts/conflict_context.py`
   It prints which commit is HEAD ("ours") and OTHER ("theirs"), the base, each side's commits, every conflicted
   hunk with the commits that wrote its lines, and **STALE NAMES**: identifiers one side removed or renamed that
   are still used somewhere, including files that merged without a conflict. Exit 1 = conflicts remain.
   In a rebase "ours" is the branch you are rebasing onto and "theirs" is your own commit: don't mix them up.

2. **Learn each side's intent before editing.** For every commit the script lists on each side, read its message
   and diff: `git show <sha>`. Write one line per side, e.g. "HEAD: weights are now grams, parameter renamed";
   "OTHER: adds an express option with a minimum weight". To see the base text of a hunk too:
   `git checkout --conflict=diff3 <file>` (only before you edit it: it recreates that file's conflict).

3. **Resolve each hunk so both intents hold.** Typical combinations:
   - one side renamed, moved or re-typed something (name, signature, unit, return shape) and the other added code
     using the old form: keep the new form and port the added code to it, including its constants and defaults;
   - both added items to the same list, enum, import block or config: keep both, in the file's order;
   - both changed the same value differently: see "When no one can answer".
   Take one side wholesale (`git checkout --ours/--theirs <file>`) only when you can say why the other side's
   change is already contained in it or obsolete; write that reason in the merge message.

4. **Fix what merged cleanly but is now wrong.** For each STALE NAME, open every listed use and port it. Also read
   the files the other side added or changed without conflict (`git diff --name-only <base> <other>`): new call
   sites, tests and docs written against the old form break silently.

5. **Bring the tests along.** Both sides' tests must still run. Update a test only to follow the other side's
   change (a renamed argument, new units), never to make a wrong result pass. Don't delete or skip tests.

6. **Check that nothing is left.**
   - `git diff --check` and `git grep -nE '^(<<<<<<<|=======$|>>>>>>>)'` show no markers;
   - `git ls-files -u` is empty after `git add <files>`;
   - the project's build, type check and full test suite pass (the command CI uses: look in CI config, `Makefile`,
     `package.json`, README). Python `python3 -m unittest` or `pytest`; JS `npm test`; Go `go build ./... && go
     test ./...`; Rust `cargo test`; Java `mvn -q test` or `gradle test`; Swift `swift test`.
   Run `conflict_context.py` once more: STALE NAMES should list nothing you haven't checked.

7. **Conclude the operation.** Merge: `git commit --no-edit` or with a message that adds one line per conflicted
   file saying how it was combined. Rebase: `git add` then `git rebase --continue` (repeat steps 1–6 for each
   stopped commit). Cherry-pick or revert: `git cherry-pick --continue` / `git revert --continue`. Stash pop:
   resolve, `git add`, then `git stash drop` only once the result is checked.

## Rules

- **Don't** pick a side for the whole file because it makes the markers go away; the other side's work is lost
  without any error and tests may not notice.
- **Don't** abort (`git merge --abort`, `git rebase --abort`), `git reset --hard` or re-run the merge with
  `-X ours`/`-X theirs` unless the user asks: it throws away the in-progress state and any resolution work.
- **Don't** delete, skip or loosen a test to get green; a failing test after a merge is usually the two intents
  disagreeing, which is exactly what you are resolving.
- **Don't** push or force-push as part of resolving.
- Don't only resolve the marked hunks: renames and unit changes break code git merged without complaint.

## When no one can answer

If the two sides set the same value or behavior to different things and nothing (commit messages, tests, issue
references) says which wins, keep the branch being merged into (main for a feature merge), make the other side's
value easy to find (a comment or constant), and list it under "decisions to review" in the merge message and the
report. Stop without committing, leaving files resolved and staged, only if tests fail and the failure needs a
product decision, or a side deleted a file the other side heavily changed and you can't tell which is right.

## Done means

- The operation is finished (merge commit made or rebase completed) and `git status` is clean of conflicts.
- No markers; `git ls-files -u` empty.
- The test command and its result, with every test from both sides still present.
- A short report: each side's intent in one line, how each conflicted file was combined, which cleanly merged
  files you changed and why, and any decisions to review.
