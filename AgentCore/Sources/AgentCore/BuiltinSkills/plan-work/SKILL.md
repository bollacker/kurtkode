---
name: plan-work
description: Use when work has several parts or spans many files or sessions, or the user asks for a plan, PLAN.md or a decision record. Small steps, each with a check, kept as a ledger. Not for vague asks (clarify-requirements).
---

# Plan work

Write a plan of small steps that each end in a check, then work through it in order, keeping the plan file as the
record of what is done and why.

## Fast path

One change in one or two files with an obvious check: no plan file; say the steps in a sentence and do them.
Write a plan when there are three or more parts, several modules, a data or file-format change, or work that may
outlast this session (or the user asks for one).

In a read-only planning mode (you can't edit files yet; kurtkode's Plan mode): do step 1, then present the plan for
approval with the harness's tool for it (`present_plan`) instead of writing `PLAN.md`; once it's approved, write the
plan file if the work is large and carry on from step 4.

## Steps

1. **Read before planning.** Find every place the work touches: entry points, data formats and their loaders
   (including old versions still accepted), serializers, validation, tests, docs and help text. Write down the
   constraints the code imposes that the request didn't mention ("existing config files have no `retries` key").

2. **Write the plan** to `PLAN.md` (or the file the user named) using the template below. Each step:
   - small enough to finish and check in one go (one behavior; roughly under 100 changed lines);
   - has a **Verify** line: the exact command and the result that proves the step works ("`python3 -m unittest
     tests.test_store` → 5 passed", "`app export --csv` → header plus 3 rows"). "Looks right" is not a check;
   - is ordered so it builds on checked ground: data model and storage before the commands that use them,
     compatibility with old data before new paths, the full suite last.
   Add steps for what the code implies, not only what was asked: old data still loads, help or docs updated.

3. **Check the plan before starting**: every requirement maps to a step; every constraint from step 1 has a step
   or a Verify that would catch breaking it; each Verify would fail if its step were skipped.

4. **Work in order.** For each step: do it, run its Verify, and only then tick it, adding the result:
   `- [x] 2. ... → 7 passed`. If the Verify fails, fix it before the next step.

5. **When reality differs from the plan, change the plan**: add, split or reorder steps and note why under
   Decisions. Don't skip a step silently.

6. **Finish** with the whole test suite and the end-to-end check from the plan's "Done when" line.

## Template

```markdown
# Plan: <goal in one line>

Done when: <observable outcome, and the command that shows it>

## Steps
- [ ] 1. <what changes, in which files>
      Verify: `<command>` → <expected result>
- [ ] 2. ...

## Decisions
- <choice> — <why> — <cost if wrong>

## Open
- <unresolved question> (default taken: <choice>)
```

For a design choice that will matter later (storage engine, protocol, library, data format), also write a short
decision record, `docs/decisions/NNNN-<title>.md`: context, options considered, decision, consequences. One screen.

## Rules

- **Don't** write the code into the plan. Name files, functions and behaviors; a plan longer than the change it
  describes has become the change.
- **Don't** do all the steps and verify at the end; a failure then can't be traced to its step.
- **Don't** tick a step without running its Verify in this session, including after a context reset or resume.
- Keep the plan file current as you go: it is what another session, or you after compaction, resumes from. Tick
  each step right after its Verify passes, not in a batch at the end: a run that stops early (step or time limit)
  must leave a plan that says truthfully what is done.
- Prefer 3–6 steps. More steps means more plan upkeep than work; merge steps that share one Verify.

## When no one can answer

Write the plan and carry on without waiting for approval. Put choices under Decisions and unresolved questions
under Open with the default you took. Stop before a step only if it is destructive or irreversible (deleting data,
publishing, pushing, migrating a shared database) and wasn't asked for; leave it unticked and say why.

## Done means

- The plan file with every step ticked and its check result, Decisions and Open filled in (or "none").
- The full suite's command and result.
- A final message naming anything left undone or unverified.
