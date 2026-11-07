---
name: code-review
description: Use when asked to review a diff, branch, commit range or pull request, or to check changes for bugs before merge. Only real bugs, each checked. Not for security audits (security-review) or answering review (respond-to-review).
---

# Review a change

Find the bugs a change introduces and report only the ones you have checked, so every line of the review can be
trusted.

## Fast path

For a diff of a few lines: read it with its whole function and its callers, check each suspicion as in step 5, and
answer in a few lines. Small reviews still contain no unchecked findings.

## Steps

1. **Get the exact change.** Use the form that matches the request:
   - uncommitted work: `git diff HEAD`, plus `git status --short` (new untracked files are not in the diff)
   - a branch: `git diff main...HEAD` (three dots: only the branch's changes) and `git log --oneline main..HEAD`
   - a commit range: `git diff A..B`; one commit: `git show <sha>`
   - a pull request: `gh pr diff N` if `gh` works; otherwise `git fetch origin pull/N/head:pr-N` and diff that branch
   List the changed line ranges in the new version:
   `python3 <skill folder>/scripts/changed_lines.py main...HEAD` (prints `path:start-end`; `--line path:N` tells
   whether one line is part of the change).

2. **Learn the intent.** Read the commit messages, the PR description, the linked issue, and project rules
   (AGENTS.md, CLAUDE.md, CONTRIBUTING). A bug is behavior that differs from the intent; the intent settles edge
   cases such as rounding, ordering, limits and defaults.

3. **Read in context, not only the hunks.** For each changed function read the whole function, its tests and every
   caller (`git grep -n "name("`). A changed return value, raised error, default or argument order breaks callers
   that the diff does not show.

4. **Hunt.** For each hunk ask "which input makes this wrong?" Look at: boundaries (`<` vs `<=`, empty, zero, one,
   last), None/null and missing keys, error paths and cleanup, changed contracts with unchanged callers, state shared
   between calls or threads, units and time zones, copies vs aliases, async calls not awaited, resources not closed.
   Run the existing tests (`python3 -m pytest -q`, `npm test`, `go test ./...`, `cargo test`, `swift test`) to learn
   what is covered; a green suite proves little about new code.

5. **Check every candidate before you write it down.** State it as "with input X, line L does Y instead of Z".
   Then prove it: trace the path that brings X to L, or run it (a one-line script, a REPL, a scratch test outside the
   repo). If you cannot name an X that reaches L, drop it or list it under Questions. If `changed_lines.py --line`
   says the line is unchanged and the change does not make it reachable, it is pre-existing: not a finding.

6. **Rank and write** (see Done means). Severity: **blocker** (wrong result, crash, data loss in normal use),
   **should-fix** (wrong in a realistic edge case), **nit** (only when the user asked for nits).

## Not findings

Drop these even when they look suspicious:
- Behavior the intent says is deliberate: the commit message, a comment or a test states it.
- A risky-looking pattern whose bad input cannot arrive: the value comes from a closed set (dict keys, an
  allowlist, an enum), an earlier check, or a type.
- Style, naming, formatting, missing docs, anything a linter or type checker reports.
- Problems in lines the change does not touch or make reachable.
- Speculation without a path: "might be slow", "could race", "may be None".
- Requests for more tests or refactoring, unless the change is unsafe without them.

## Rules

- **Don't** report a finding you have not checked against the code: one false alarm costs the author more time
  than it saves and makes them distrust the rest.
- **Don't** pad the review. Zero findings is a valid result; then say what you checked.
- Don't edit the code under review unless asked: the review is the deliverable.
- Cite line numbers in the new version of the file (`path:line`), so the author can jump to them.
- Posting comments on a hosted PR is public: do it only when asked.

## When no one can answer

If the intent is unclear, infer it from tests, docs and callers, state the assumption in the review ("assuming
discounts start at 10 units, as the commit message says"), and judge against it. Put real unknowns under
Questions. Finish the review; don't stop to ask.

## Done means

The review, in the file the user named or in your reply, in this shape:

```
Reviewed: <range>, <n> files. Ran: <test command and result, any repro scripts>.

## Findings
- path:line — blocker|should-fix: what is wrong. Trigger: the input or call. Result: what happens vs what should.
  Fix: one sentence.

## Questions
- things you could not decide from the code and docs

## Checked, not a problem
- short notes on suspicions you dropped and why (optional)
```

One bullet per finding, most severe first. A finding's bullet starts with `path:line`; nothing else does.
