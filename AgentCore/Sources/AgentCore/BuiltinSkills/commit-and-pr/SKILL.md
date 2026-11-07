---
name: commit-and-pr
description: Use when asked to commit, split changes into commits, write a commit message, or open or describe a pull request. Gives focused commits, no secrets, PR text with how it was verified. Not for conflicts (resolve-merge-conflicts).
---

# Commit work and describe the pull request

Turn a working tree into commits that each do one thing and say why, with nothing committed that shouldn't be, and
a PR description a reviewer can check.

## Fast path

One concern, a few files, nothing untracked you didn't create: read `git status` and `git diff`, stage the files by
name, run the staged check (step 4), commit with a message that says why. Still never `git add -A`.

## Steps

1. **Inventory.** `git status --porcelain -uall`, `git diff`, `git diff --cached` (something may already be staged:
   keep it unless it is wrong), and `git log --oneline -15` for the house message style (Conventional Commits,
   ticket prefixes, tense). Open every untracked file before deciding about it.

2. **Sort every changed file (or hunk) into one bucket:**
   - a **concern**: one reason to change (a bug fix, a feature, a refactor, a dependency bump). A feature and its
     tests and docs are one concern; an unrelated fix found on the way is another.
   - **never commit**: secrets and local config (`.env*`, `*.pem`, `*.key`, `id_rsa*`, `credentials*.json`,
     `*.p12`, tokens in any file), debug and scratch files (`debug_*`, `scratch*`, `tmp*`, `*.log`, dumps), build
     output, editor and OS files, large binaries nobody asked for.
   - **unsure**: leave it out and list it in the report.

3. **Stage one concern at a time, by path:** `git add path/a.py tests/test_a.py`. When one file holds two concerns,
   stage part of it without an interactive prompt: `git diff path > /tmp/p.diff`, delete the other concern's hunks
   from the copy, `git apply --cached /tmp/p.diff`, then check with `git diff --cached path`.

4. **Check what is staged before every commit:**
   `python3 <skill folder>/scripts/check_staged.py`
   It lists staged files and flags secret-like files and lines, debug leftovers (`breakpoint()`, `console.log`,
   `debugger`, `print("DEBUG`), conflict markers and large files. Exit 0 = clean, 1 = something flagged (each line
   says what and where), 2 = not a git repo. Unstage what it flags (`git restore --staged <path>`) or remove the
   leftover line, unless it is clearly intended (say why in the report).

5. **Make each commit build and pass on its own.** Code and the tests for it go in the same commit. If tests are
   cheap, run them after each commit; at minimum run the full suite once at the end and name the command.

6. **Write the message.** Subject: imperative, ≤ 72 characters, says what changed in project terms ("Fix slugify
   leaving hyphens at the ends", not "update utils"). Body: why (the bug, the request, the constraint) and how it
   was verified. Follow the house style found in step 1.
   `git commit -m "<subject>" -m "<why and how verified>"`

7. **Protect what you left out.** Secret files that git does not ignore: add them to `.gitignore` in their own small
   commit (check with `git check-ignore -v .env`). Don't delete or move the user's files.

8. **PR description** (when asked for a PR, or write it to the file the user names). Use this shape:
   ```
   ## What and why        two or three sentences, the problem first
   ## Changes             one line per commit or concern
   ## How it was verified exact commands run and their result ("python3 -m unittest: 14 passed")
   ## Not verified / risks what you could not check, migrations, config, follow-ups
   ```
   With a remote and a CLI (`gh pr create --title ... --body-file ...`, `glab mr create`) open it only if the user
   asked to open it; otherwise leave the text in a file and say where.

## Rules

- **Don't** run `git add -A`, `git add .` or `git commit -a`: they sweep in `.env` files, debug scripts and
  half-finished edits that were never reviewed.
- **Don't** commit a secret even when the user says "commit everything"; leave it out and say so. If one is already
  in history, deleting it in a new commit doesn't help: tell the user to rotate it.
- **Don't** bundle unrelated changes to save time; a reviewer can't revert or bisect half a commit.
- **Don't** skip hooks with `--no-verify`; fix what the hook reports.
- **Don't** amend, rebase or force-push commits that are already pushed, and don't push at all unless asked.
- Don't reformat or touch lines outside the change; whitespace churn hides the real diff.

## When no one can answer

Split by concern as you judge it, put an unclear file with the concern whose tests exercise it, leave out anything
secret-like or scratch-like, and list each such choice in the report. Stop without committing only if the only way
to commit is to include a secret, or a hook needs credentials or services you don't have.

## Done means

- `git log --oneline <start>..HEAD`: each commit one concern, a specific subject and a why in the body.
- `git status` afterwards, with every file you left out named and the reason (secret, debug, unsure).
- The test command you ran and its result.
- The PR description (file path or PR link) with all four sections, when a PR was asked for.
