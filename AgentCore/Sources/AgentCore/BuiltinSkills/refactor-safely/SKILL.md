---
name: refactor-safely
description: Use when asked to clean up, restructure, split, extract or untangle code without changing what it does, especially code with few tests. Behavior pinned first, small green steps. Not for renames across many files (codemod).
---

# Refactor safely

Change the structure of code without changing its behavior: pin what it does first, move in small steps, and run
the pins after every step.

## Fast path

A rename or a single extraction in code that existing tests clearly cover: run the tests, make the move, run them
again, read the diff. If no test fails when you break the code on purpose, the code is not covered: use the steps.

## Steps

1. **Draw the boundary.** What must not change: signatures, return values, exceptions (type and when), output
   format, side effects (files, input objects mutated, logs other tools parse). Find the callers (`grep -rn name`)
   and note what each relies on. Everything inside the boundary may change.

2. **Pin the current behavior before any edit.**
   - Run the existing tests. Check they really cover this code: break one line, run, restore.
   - Add characterization tests: inputs that reach every branch, with expected values **pasted from running the
     current code**, not worked out by reading it. Name or comment them "pins current behavior".
   - For code with many branches or arithmetic, add a differential check as well: keep a copy of the original
     outside the project (`git show HEAD:path/to/file > <scratch>/orig_file`), feed both versions a few thousand
     seeded random inputs that cover the branches, and compare results, exceptions and mutated inputs:

     ```python
     orig = load_module("<scratch>/orig_billing.py")      # importlib.util.spec_from_file_location
     rnd = random.Random(1)
     for _ in range(5000):
         x = random_order(rnd)       # empty lists, zeros, negatives, every code/category/flag, boundary values
         a, b = outcome(orig.compute_invoice, deepcopy(x)), outcome(new_compute_invoice, deepcopy(x))
         assert a == b, (x, a, b)    # outcome() returns the result or the exception type
     ```
   Run all pins on the untouched code: they must pass.

3. **Plan the moves.** List small, behavior-preserving moves: extract function, rename, inline, introduce a
   parameter object, replace nested conditions with early returns, move code to another module.

4. **One move at a time.** After each move run the pins and the tests.
   - Green: checkpoint (a WIP commit, or `git add` to stage it if the user doesn't want commits), then the next move.
   - Red: undo the move (`git checkout -- <file>` restores the last staged or committed state). Don't debug
     forward from a red refactor; make a smaller move instead.

5. **Keep the odd parts exactly.** Code that looks wrong is still behavior. Watch for: a loop variable used after
   the loop; counters that include skipped items; `a and b or c` precedence; rounding at particular points; float
   addition order; checks against `== 0` that treat missing and zero alike; input objects mutated in place; dict or
   set iteration order; exceptions raised before or after a side effect. Preserve them, add a short comment where
   it helps the next reader, and list them in the report as candidate fixes.

6. **Finish.** Full test suite, the differential check one last time, then read the whole diff. Keep the
   characterization tests in the project; delete the scratch copy and any driver script.

## Rules

- **Don't** fix bugs or TODOs during a refactor, however obvious, even if a comment asks for it. Callers, stored
  results and audits depend on today's behavior. A fix is a separate change, with its own test, made only if asked.
- **Don't** write expected values for pins by reasoning about the code. Run it and paste the output.
- **Don't** mix a structural change and a behavior change in one step or commit.
- **Don't** keep going on red. Revert the step.
- **Don't** change a public signature unless asked. If you must, leave a compatibility wrapper and say when it
  can go.
- A mechanical change across many files (rename an API everywhere) is codemod work, not this.

## When no one can answer

If a quirk might be a bug, keep it, comment it, and list it under candidate fixes; don't ask and wait. If the code
cannot be run at all (missing services, no interpreter), don't refactor: report what you would need. If the
request mixes "clean up" with a behavior change, do the refactor first, prove it neutral, then make the behavior
change as a separate step with its own test.

## Done means

- Characterization tests added (file, number of cases, the branches they reach) and passing before and after.
- The differential check's result: how many inputs, zero differences.
- The list of moves made, each followed by a green run, and the final full-suite command and result.
- Quirks preserved, with file:line, as candidate fixes for a later change.
