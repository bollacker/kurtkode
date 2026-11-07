---
name: clarify-requirements
description: Use when a request is vague or reads several ways ("add a way to...", "make it better", "support X") and the details decide the result. Turns it into checkable acceptance criteria. Not for agreed work (plan-work).
---

# Clarify requirements

Turn a vague request into a few acceptance criteria before building: ask where someone can answer, and choose the
safe reading and record it where no one can.

## Fast path

If the request has one sensible reading, or the repo settles the open points (existing patterns, docs, tests,
schema), write the criteria in two or three lines and build. Ask nothing the code already answers.

## Steps

1. **Look before asking.** Read the code, schema, docs, tests and data the request touches. Note what they already
   settle and what they protect: conventions, constraints (foreign keys and cascades, NOT NULL, unique keys),
   other readers of the same data (reports, exports, other services), documented promises.

2. **List the open points.** For each, write the readings that lead to different code. "Remove a project" = delete
   the row / archive it / hide it from lists but keep its history. Usual open points: scope (which commands,
   users, data), what happens to existing data, defaults and edge cases (empty, duplicates, limits, repeats),
   errors, compatibility (old files, old clients, existing callers), who is allowed.

3. **Rank by the cost of a wrong guess.** A point matters if a wrong guess destroys data, breaks other callers or
   reports, is visible to users, or is hard to undo. For the rest, follow the repo's convention and move on.

4. **Ask, if someone can answer.** One message with the points that matter (at most five), most important first,
   each a question with your proposed default and the evidence:
   "Removing a project cascades to its invoices (schema.sql:22), which feed billing. Archive it and keep the
   invoices instead? (default: yes)". Then wait for the answer.

5. **Write acceptance criteria**: observable statements a test or a command can check. "After
   `archive_project(5)`, `list_projects()` omits project 5 and the March invoice total is unchanged." One per point from step 3,
   plus the main non-goals ("no admin UI").

6. **Build to the criteria**, then check each one with a test or a command.

## Choosing the safe reading

When readings differ in risk, prefer, in this order:
1. the one that keeps data and can be undone (mark, flag or archive over delete; add over replace);
2. the one that keeps existing callers, files, reports and tests working;
3. the one that matches how the repo already does similar things;
4. the narrower scope: what was asked, not what might be wanted next.

Make the chosen reading hold everywhere the data is read: an archived or hidden row must also be left out of
lookups, lists, counts and exports that the request's users see, and kept where history is needed (reports,
audits). Find those readers with a search before building. Say in the record what the other reading would take,
so switching later is cheap.

## Rules

- **Don't** build the literal word when it conflicts with what the code protects ("delete" next to a cascade into
  financial records). The literal reading is the risky one there.
- **Don't** ask what the repo already answers, and don't ask more than five questions at once.
- **Don't** add features to cover several readings (settings, undo commands, admin screens); record them as
  options instead.
- Don't present a guess as a requirement: every default you chose is written down as an assumption.

## When no one can answer

In `-p` runs, subagents and full-auto modes nobody replies: don't stop and don't wait. Choose the safe reading for
each open point, build it, and record the assumptions in the file the user named, else `ASSUMPTIONS.md` at the
repo root, and repeat them in your final message. Each assumption: the question, the choice, the evidence
(`path:line`), and what would change if the answer is different. Stop without building only when every reading
risks harm that can't be undone (deleting real data, sending messages, spending money).

## Done means

- Acceptance criteria written down (assumptions file, plan, or PR text).
- The work built to them, with each criterion checked: the test or command and its result.
- Assumptions listed with their evidence and the alternative, in the file and in the final message.
