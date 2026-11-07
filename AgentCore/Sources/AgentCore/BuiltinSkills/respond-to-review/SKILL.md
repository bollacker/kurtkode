---
name: respond-to-review
description: Use when a reviewer, teammate or bot left comments on your PR, diff or code and you must address them or reply. Checks each comment against the code before changing it. Not for reviewing someone else's change (code-review).
---

# Respond to review comments

Apply the review comments that are right, answer the ones that are wrong with evidence, and reply to every one.

## Fast path

One or two small comments whose fix you can see on the line (a typo, a missing check): confirm in the code, fix,
run the tests, reply "Fixed: …". Any comment that states a fact about other code still gets step 3.

## Steps

1. **Collect every comment first.** Make a ledger before you change anything: number, file:line, what it asks,
   kind (bug, change request, question, preference, out of scope), status. Sources: a file the user names, PR
   threads (`gh pr view N --comments`, `gh api repos/OWNER/REPO/pulls/N/comments`), bot output. Read them all:
   a later comment can change or contradict an earlier one.

2. **Restate each as a checkable claim.** "parse_status raises IndexError on an empty line", "config.load already
   rejects 0". If you can't restate it, it goes to Questions.

3. **Check each claim against the code, not against the reviewer's confidence.**
   - Open the lines; if the code moved since the review, find where it went.
   - Follow every claim about other code ("X already validates this", "this can't be None", "unused") to that
     code and read it: `git grep -n "name"`.
   - Prove bugs by running them: a one-line script or a test that fails now.
   - Before deleting "dead" code, find the input that reaches it (tests, docs, config files, old data).

4. **Decide per comment.**
   - Right: make the change.
   - Right problem, wrong fix: fix the problem another way and explain.
   - Wrong (the claim is false, or the change breaks callers, a documented contract, tests or a platform): don't
     change the code; reply with the evidence (file:line, test name, command output).
   - Preference with no project rule against it: usually follow it; it is cheap.
   - Out of scope ("while you're here, also…"): reply and suggest a follow-up; keep this change small.

5. **Implement one comment at a time.** Smallest change; add or adjust a test that pins the behavior the comment is
   about (for a bug, one that fails before the fix); run the tests after each change. If the user wants commits,
   one commit per comment or logical group, with the comment number in the message.

6. **Run the whole test suite** once all changes are in, then write the replies.

## Rules

- **Don't** apply a suggestion only because a reviewer made it. Reviewers see the diff, not the whole program; a
  wrong change you apply is your bug.
- **Don't** change a contract (validation, defaults, public API, config format) to make a reviewer's claim true.
  If "load() already rejects 0" is false, the answer is a reply, not a new rejection that breaks existing configs.
- No performative agreement in replies ("Great catch!", "You're absolutely right"). Say what changed and where.
- Never skip a comment silently: declined and deferred comments get a reply too.
- If you pushed back and later find you were wrong, say so in the reply and fix it.
- Don't post replies, resolve threads or re-request review on a hosted PR unless asked; write the replies where the
  user asked, or in your answer.

## When no one can answer

Decide each comment on the evidence. If the code shows the reviewer is right, apply it; if it shows they are wrong,
decline with evidence; if the evidence doesn't settle it, keep the current behavior and tests, and mark the reply
"open question" with what would settle it. Stop instead only if a comment asks for something destructive or outside
the repo (rewriting pushed history, changing production config, deleting data).

## Done means

- The code changes, and the test command with its result.
- A reply for every comment, in the place the user named, in this shape:

```
## Comment N
Fixed: what changed (file:line). Test: test name.
  or: Not changed: why, with evidence (file:line, command and output).
  or: Changed differently: the problem, what you did instead, why.
  or: Question: what is unclear and the option you chose meanwhile.
```

- A summary line: applied N, declined M, open K.
