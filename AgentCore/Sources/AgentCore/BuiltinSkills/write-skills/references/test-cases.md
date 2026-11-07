# Test cases for a skill

Read this when writing `cases.json` and the task test for a skill (step 7 of the skill).

## Layout

```
eval/cases/<skill>/
  cases.json
  fixtures/<case id>/          the project the agent starts in (copied, then git-initialized)
  fixtures/<case id>/_setup.sh optional: builds history, branches or uncommitted work instead of one commit
  hidden/                      files only the check uses (hidden tests, expected outputs)
  reference/<case id>.sh       a solution run in the project folder; proves the check can pass
```

## cases.json

```json
{
  "triggers": {
    "should": ["5+ varied requests that need the skill, most without naming the technique"],
    "should_not": ["3+ near misses: sound close, but another skill or no skill owns them"]
  },
  "tasks": [{
    "id": "short-id",
    "fixture": "fixtures/short-id",
    "prompt": "what a user would type; never names the skill",
    "check": "python3 \"$CASE_DIR/hidden/check.py\"",
    "rubric": ["3-5 things a reader of the transcript can see, e.g. 'ran the check before committing'"],
    "max_steps": 40
  }]
}
```

## Trigger requests

- **Should**: vary the wording, the length and the entry point (a symptom, a file name, an error message, a
  command). At most one or two may name the technique outright.
- **Should not**: mostly requests that share words with the skill but belong to a sibling skill (for a migration
  skill: "write a query that sums entries", "fix the rows posted to the wrong account"); plus one plain question
  no skill needs. Unrelated requests ("make a website") test nothing.

## A task with a trap

A task only teaches something if a capable agent **without** the skill plausibly fails it and the skill's
guidance avoids that. Build the trap from the failure named in step 1:

| Failure the skill fights | Trap in the fixture |
|---|---|
| sweeps everything into one commit | an `.env` with a token and a scratch file next to real work |
| copies a bad local example | an existing file with the wrong shape to imitate |
| fixes only the visible symptom | a second break the obvious fix leaves (a file that merged cleanly, a second caller) |
| skips the house check | a failure only the project's own check script reports |

Keep the fixture small (a few files, under ~300 lines), standard tools only (Python 3, Node, git, sqlite3, bash),
no network. The prompt works without follow-up questions and asks for text answers in a named file.

## The hidden check

- Exit 0 = pass, anything else = fail; print one `FAIL: <reason>` line per problem.
- Objective: run hidden tests, compare exact values, inspect git history, match key strings in a written file.
  Never only "the file exists".
- It must **fail on the untouched fixture** and **pass after the reference**. Run both before trusting it.
- Allow every correct solution: check behavior, not the exact code or wording you would have written.
