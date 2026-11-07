---
name: handoff-notes
description: Use when asked to stop mid-task or pass work to another session, agent or person ("leave notes", "save where we are"). Writes a HANDOFF.md. Not for your own context running low (it gets summarized) or plans (plan-work).
---

# Write handoff notes

Leave a file from which a fresh session, with none of this conversation, can continue the work correctly.

Write notes when the user asks for them or the work has to stop. Your own context filling up is not a reason to
stop: the conversation is summarized when it gets long, and the work goes on.

## Fast path

Nothing uncommitted and the next step is obvious: five lines are enough (goal, branch and last commit, the verify
command and its result, the next step, anything not to redo). The verify command is the one CI runs (step 1 says
where to look), not the default test runner: they often differ, and the difference is what the next session trips
on. Run it; don't recall it.

## Steps

1. **Collect the state by running, not remembering.**
   - `git status --short`, `git branch --show-current`, `git log --oneline -5`, `git diff --stat`,
     `git stash list`; note untracked files that matter.
   - Find the project's verify command: the one CI runs (`.github/workflows`, `Makefile`, `package.json`
     scripts, `tools/`, README "before pushing"). Run it. Copy the names of failing tests and checks exactly,
     with the first line of each error. If you only ran part of it, say which part.
   - Read existing notes (NOTES.md, PLAN.md, TODO, JOURNAL, issue text) all the way to the end.

2. **Pick out decisions.** For each choice made so far: what was chosen, why, and what it replaced. When notes
   contradict each other, the latest dated or "changed:" entry wins; record the earlier one as rejected so nobody
   goes back to it. A decision with no recorded reason: write "reason not recorded".

3. **Write HANDOFF.md** at the repository root (or where the user or project keeps them; update an existing one in
   place rather than adding a second file). Use this shape:
   ```
   # Handoff: <task> (<date>)
   Branch `<branch>` at <short sha> "<subject>"; uncommitted: <files> | none.

   ## Goal
   <one or two sentences; link the issue or spec>

   ## State
   - Done: <what works, with file paths>
   - In progress: <file: what is there and what is missing>
   - Verify: `<exact command>` -> <result now: passed | failing: <test or check> (<first error line>)>

   ## Decisions
   - <decision> because <reason>. Replaces: <earlier idea> (don't go back to it).

   ## Next steps
   1. <first concrete action: file, function, what "done" looks like for it>
   2. ...

   ## Open questions and risks
   - <what is unknown, who might know, what could break>
   ```
   Leave out empty sections rather than writing "none" everywhere, but always keep State, Verify and Next steps.

4. **Read it as a stranger.** Every path exists; every command runs from the repository root as written; no "the
   bug we saw" or "as discussed"; test names are copied, not paraphrased. Fix what fails this.

5. **Leave the work as it is.** Don't commit, stash, reset or finish code while writing the handoff unless asked:
   the notes must describe the state the next session will actually find. If the environment will be deleted
   (a temporary worktree or container) and the user allowed commits, commit the work in progress to a branch
   named `wip/<task>` and say so in the notes.

## Rules

- **Don't** write "tests pass" or "almost done" without the command and its output from this session; the next
  session will trust it.
- **Don't** describe only the plan; the reader needs what is true now, including what is broken.
- **Don't** put secrets, tokens or personal data in the notes; name where they live instead (`.env`, a vault).
- Keep it short (under ~60 lines): point to files and commits instead of pasting them.

## When no one can answer

Write the notes from what the repository and its files show, mark anything you inferred as "(inferred)", and list
questions for the user under "Open questions" instead of asking. If the verify command can't run (missing
dependencies, services), write the command, why it didn't run, and what you ran instead.

## Done means

HANDOFF.md exists with: branch and last commit, the uncommitted files, the exact verify command and its current
result (failing tests named), the decisions with reasons and what they replaced, and a numbered next step concrete
enough to start on without asking. The working tree is otherwise unchanged. Tell the user the file's path.
