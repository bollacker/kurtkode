---
name: navigate-code
description: Use when asked how something works in a repo, where a value or request ends up, what calls what, or what a change would affect. Traces the real path end to end, citing file:line. Not for why code was written so (code-history).
---

# Navigate code

Answer questions about how a codebase behaves by following the calls that actually run, so every claim rests on a
line you read.

## Fast path

If the question is about one function or one file, read it and answer with `path:line`. Use the steps when the
answer crosses modules, when more than one place could be the answer, or when the reach of a change matters.

## Steps

1. **Pin the question to two ends.** Name the entry point (the command, route, job or test that starts it) and the
   end point (where the value is *used*, the side effect, the output). "What retry limit does `worker sync` use"
   runs from the worker's `main` to the call that applies the limit, not to the place where a default is defined.

2. **Map quickly; don't read everything.** `git ls-files | head -200` (or `find . -maxdepth 2 -not -path
   './.git*'`); the README; the manifest (`pyproject.toml`, `package.json`, `go.mod`, `Cargo.toml`,
   `Package.swift`, `pom.xml`); the entry point's file; config files; where the tests live.

3. **Search for candidates.** `rg -n` or `grep -rn` for the name, the literal, the config key, the flag, the error
   text. Every hit is a candidate, not an answer: a default, a legacy copy, a test value, another config section,
   a stale doc.

4. **Follow the path from the entry point.** Read each call in order until the end point and write one line per
   hop: `path:line — what happens to the value`. At each hop look for what can change it later: config over
   defaults, environment or arguments over config, unit conversions, clamps (`min`/`max`), fallbacks, exception
   handlers that substitute a value, dispatch tables, decorators, dependency injection, subclasses overriding.
   Keep going to the line that consumes the value; the last write wins.

5. **Rule out the other candidates.** For each candidate from step 3 not on the path, find why: no callers
   (`grep -rn name` finds only its definition), reached only from tests, another section or mode. A function
   with the right name and no callers is the most common wrong answer; a README number is the second.

6. **Confirm by running when it's cheap.** If a test, a REPL line or a temporary print at the end point can show
   the value, run it and compare with the trace. If they differ, the trace missed a hop; go back to step 4.
   Remove every temporary edit (`git diff` must be empty when you finish a question).

7. **For "what does changing X affect":** find every reader of X — callers and imports, the config key, the
   serialized field or column name, the CLI flag, fixtures, migrations, docs and tests — and list each with
   `path:line` and whether it must change. Include places that limit X downstream (step 4's clamps and
   validators): changing X alone may have no effect.

In a large repo, hand steps 2–3 to a subagent with a fixed return shape (candidate files and `path:line` hits, no
prose) so its reading doesn't fill your context; do step 4 yourself.

## Rules

- **Don't** answer from a name, a default or a doc: `DEFAULT_*`, a constant, a docstring or the README says what
  someone intended, not what runs. Trace to where the value is used.
- **Don't** stop at the first plausible source; later hops override earlier ones.
- Every claim cites `path:line`. What you didn't read is labeled "not checked", not stated as fact.
- **Don't** change code to answer a question. Temporary prints are fine if removed.

## When no one can answer

If the question is ambiguous (which entry point, which environment, which config file), answer for the documented
or default one, say which you chose, and add the other answer in one line if it differs. Stop only where the path
leaves the repo (a remote service, a closed binary) and say exactly where it leaves.

## Done means

In the file the user named, or your reply:
1. **The answer first**, in the shape asked for (the value, the list of files, yes/no).
2. **The path**: numbered hops, `path:line — what happens`.
3. **Decoys ruled out**, each with the reason.
4. **Not checked**: anything you inferred without reading, and how you confirmed the rest (trace only, or run).
