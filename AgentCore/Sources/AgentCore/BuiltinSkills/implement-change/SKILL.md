---
name: implement-change
description: Use when adding a feature or a specified change to existing code (a new option, field, endpoint or command) or the next step of an agreed plan. Builds it the codebase's way. Not for restructuring (refactor-safely).
---

# Implement a change

Make a requested change the way this codebase would: built on its existing helpers and patterns, in small steps
that are each checked.

## Fast path

A one-file change with an obvious place and a working test command: read the surrounding code and the helpers it
already imports, make the change, add a test, run the suite. The rules below still apply.

## Steps

1. **Read first.** Read the code you'll change and its callers. Find the closest existing feature that does
   something similar (another flag, endpoint, report line, refund rule) and read how it is built and tested.
   If the change deletes or overwrites stored data, find what depends on it (foreign keys and `ON DELETE
   CASCADE`, reports, other readers). When the literal change would destroy records others rely on (orders,
   payments, audit history), build the non-destructive version instead (mark, archive or anonymize) and say so;
   noticing the cascade and deleting anyway is the failure this step exists to stop.

2. **Find the house way before writing anything new.** Search for helpers for the job:
   `grep -rn` / `rg -n` for the domain words (money, cents, percent, date, tz, slug, retry, path, escape,
   validate) and look in the modules the neighbors import and in `util`, `helpers`, `common`, `lib`. Open them
   and read their docstrings. If one exists, use it even when inline code looks simpler: it encodes rules
   (rounding, formatting, time zones, escaping, error types) that the rest of the code and its users rely on.
   Match the neighbors' naming, error handling, logging and test style.

3. **Get a baseline.** Run the existing tests before editing, so later failures are known to be yours:
   `python3 -m pytest -q` or `python3 -m unittest discover -s tests`, `npm test`, `go test ./...`,
   `cargo test`, `swift test`, `mvn -q test`, or what the README / CI config uses.

4. **Smallest step, then check.** Change one thing, run the relevant test or a one-line command that exercises
   it, then take the next step. Add tests next to the existing ones for the new behavior and the edges the
   feature implies: zero and empty, rounding boundaries, large values (separators, overflow), negatives,
   the unchanged default path.

5. **New or unfamiliar library, API or language feature:** check what is installed, not what you remember:
   the lockfile, `pip show <pkg>`, `python3 -c 'import x; print(x.__version__)'`, `npm ls <pkg>`, `go list -m all`.
   Read its docs or source in the environment (`python3 -c 'help(x.f)'`, `node_modules/<pkg>/README.md`,
   `go doc`). Use only what that version provides.

6. **Finish.** Run the whole suite. Read your `git diff`: no debug prints, no unrelated edits, no logic that
   duplicates a helper. Check the result against each part of the request, including "unchanged" parts.

## Rules

- **Don't** write a new helper or inline the logic when the codebase has one for the job (money, dates, paths,
  HTTP, validation, formatting). A duplicate drifts: it will round, format or escape differently.
- **Don't** do money or date arithmetic with floats, `round()` or `f"{x:.2f}"` when a domain module exists.
- **Don't** reformat, rename or tidy unrelated code on the way; it hides the real change in review.
- **Don't** delete or overwrite stored data before checking what depends on it (foreign keys and cascades,
  reports, other readers). If the literal change would destroy history others rely on, treat the request as
  ambiguous and follow the clarify-requirements skill.
- **Don't** change an existing test's expectation to make your code pass; if the request conflicts with a test,
  say so.
- Don't add a dependency when the standard library or an installed package already does the job.

## When no one can answer

If the request leaves a detail open, follow the nearest existing feature and record the choice as an assumption
in your final message. If the request's wording and the house helper disagree (the request shows a format the
helper doesn't produce), produce the requested output, keep the helper for the logic, and say so. Stop only for a
decision with lasting cost nobody asked for (a schema change, a public API break, a new service).

## Done means

- The change and tests for its new behavior, next to the existing tests.
- The full suite passing: the command and its result.
- A short report: files changed, which existing helpers and patterns it reuses, assumptions, and anything not
  verified.
