---
name: code-history
description: Use when asking why code is the way it is (who changed a line, when, and why) or before removing an odd constant, workaround or check. Finds the origin commit past renames. Not for finding a breaking commit (bisect-regression).
---

# Code history

Find the commit and the recorded reason behind a line of code, so a change to it is made knowing why it exists.

## Fast path

Run `python3 <skill folder>/scripts/line_history.py <file> --match '<regex for the line>'`. If the ORIGIN commit's
message or the test it added explains the line, report that (step 6 and the report) and stop.

## Steps

1. **Locate the line** in the current tree: file and line number (`grep -n`).

2. **Get the line's history** through renames and reformatting:
   `python3 <skill folder>/scripts/line_history.py <file> --line N` (or `--match REGEX`).
   It prints the file's earlier paths, every commit that changed that line (newest first) with the before/after
   text, the full message and the files touched; it tags commits where only formatting or names changed
   `[values unchanged]`, names the ORIGIN commit (the oldest that introduced the line's current numbers and
   strings), and lists other commits anywhere that added or removed those literals (PICKAXE).
   Exit 0 = history printed; 1 = the line has no committed history (new or uncommitted); 2 = usage error.
   Without the script: `git log -L N,N:<file>`, `git blame -w -M -C -C <file>`, `git log --follow -p -- <file>`,
   `git log -S'<literal>' --all`, `git log -G'<regex>' --all`.

3. **Skip the commits that only moved it.** Renames, reformatting, mass renames, type hints and merges are not the
   reason. Go back until the commit where the value or the logic actually changed. `git blame` shows the last
   touch, which is usually one of these.

4. **Read the origin commit in full**: `git show <hash>` — the whole message body, not only the subject; the other
   files it changed, above all tests added with it (a test names the case the code guards); issue, incident or
   ticket IDs. Search for those IDs too: `git log --all --grep='<ID>'`, `grep -rn '<ID>' .`.

5. **Widen if the message is thin**: the same author's neighboring commits (`git log --since=… --until=…`), the
   merge that brought it in (`git log --merges --ancestry-path <hash>..HEAD`), the CHANGELOG or docs at that
   commit (`git show <hash>:CHANGELOG.md`).

6. **Judge whether the reason still holds.** Look in the current code and docs for what the reason depends on (the
   vendor, the bug, the library version, the guarding test). If nothing shows it was resolved, treat it as live.

## Rules

- **Don't** report the last commit that touched the line as the one that introduced it. Blame stops at
  reformatting and renames.
- **Don't** invent a reason from the code's shape or a vague comment ("for safety", "probably for
  speed"). If no commit, test or doc gives one, say "no recorded reason" and list what you checked.
- **Don't** change the code while investigating; the user decides after reading the reason.
- Quote the reason with its source (hash, file); don't strengthen or soften it in a paraphrase.
- Read-only git only: no checkout of old commits in the working tree (use `git show <hash>:<path>`), no reset,
  rebase or fetch.

## When no one can answer

Decide from the evidence alone. If the history is shallow (`git rev-parse --is-shallow-repository` prints
`true`), say so and report what is visible; don't fetch more without being asked. If there is no recorded reason,
say so, give the safest next step (for example a test that pins the current behavior before changing it), and
answer "unknown" rather than "safe".

## Done means

A short report (in the file the user named, if any) with:
- **origin**: hash, date, author, subject of the commit that made the line what it is;
- **reason**: quoted from the message, test or doc, with where it came from;
- **path**: renames and cosmetic commits skipped on the way;
- **still applies?**: yes / no / unknown, with the evidence;
- the answer to the user's actual question (for example "safe to remove: no, because …").
