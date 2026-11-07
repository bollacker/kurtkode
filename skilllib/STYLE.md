# Writing a skill for this library

Every skill in `skills/` follows this guide; every skill has tests in `eval/cases/<skill>/`. Read `EVALUATION.md` for
why. The short version: skills help only where the model lacks knowledge or reliably misbehaves, long skills hurt,
and a skill that doesn't beat the no-skill baseline on its own test gets cut or rewritten.

## Folder

```
skills/<name>/
  SKILL.md            required
  scripts/            optional: tools the skill runs (python3 stdlib or POSIX bash)
  references/         optional: detail read only when SKILL.md points to it (one level deep)
```

## Front matter: only `name` and `description`

```yaml
---
name: fix-flaky-tests
description: Use when a test passes on some runs and fails on others, fails only in CI or only with other tests, or depends on timing or order. Proves the flake, finds the cause, fixes it. Not for tests that always fail (systematic-debugging).
---
```

- `name` = folder name, lowercase-hyphen.
- `description` ≤ 230 characters. Shape: **"Use when …"** with concrete triggers and the words a user would type
  (symptoms, file types, commands), then **what it gives in ≤ 10 words**, then **"Not for …"** naming the sibling
  skill when there is a near miss. Don't summarize the steps (agents follow the summary instead of the skill).
- No other fields (they break portability: opencode ignores them, claude.ai rejects them).

## Body

Target **60–150 lines, under 6 KB**. Small local models must be able to follow it. Put long tables, per-language
command lists and examples in `references/` and say exactly when to read them.

Sections, in this order (omit what doesn't apply):

1. `# Title` and one sentence: what this skill makes happen.
2. `## Fast path` — when the task is small or the answer obvious, what the skill reduces to (2–4 lines). Every
   process skill has one: proportionality is a gap in the published skills.
3. `## Steps` — numbered, imperative, each one checkable. Name the commands. Give commands for several stacks where
   they differ (Python, JS/TS, Go, Rust, Swift, Java) or point to a reference file.
4. `## Rules` — discrete prohibitions, only for known agent failure modes ("Don't change a test's expected value to
   make it pass"). Each with a reason in a few words. No all-caps shouting; one bold word is enough.
5. `## When no one can answer` — in `-p` runs, subagents and full-auto modes nobody replies: what to decide alone,
   how to record the assumption, and the few things that still justify stopping.
6. `## Done means` — the output contract: what exists at the end (a file and its shape, a report's sections, evidence
   such as the test command and its result).

Match the form of an instruction to the failure it fights:
- discipline failure (skipping a step under pressure) → a discrete rule plus the excuse it blocks;
- output-shape failure (wrong format, missing parts) → a positive recipe or a template;
- omission → a required slot in the output contract;
- judgment calls → conditions on things the agent can observe ("if the test passes before your change, …").

Don't write what a capable model already does well. No tutorials, no history, no "best practices" lists without a
decision attached. Plain language; no marketing words.

## Scripts

- `python3` standard library or POSIX `bash` only; no network; no installs.
- First lines: what it does, usage, **exit codes** (0 = success/clean, 1 = the thing was found / check failed,
  2 = usage error), and what it prints.
- Safe by default: never rewrite history, delete files or discard work unless given an explicit flag; restore state
  on exit (e.g. `git bisect reset`).
- `--help` works. Output is short and parseable (the agent reads it).
- SKILL.md says when to run it and how to read its output.

## Tests: `eval/cases/<skill>/`

```
eval/cases/<skill>/
  cases.json
  fixtures/<case id>/        the project the agent starts in (copied, git-initialized)
  fixtures/<case id>/_setup.sh   optional: builds git history/branches/conflicts instead of the single commit
  hidden/                    optional: files the check uses that the agent must not see (tests, mutants)
  reference/<case id>.sh     a reference solution, run in the project folder; proves the check can pass
```

`cases.json`:

```json
{
  "triggers": {
    "should":     ["≥5 requests that should load this skill, varied, most NOT naming the technique"],
    "should_not": ["≥3 near misses: requests that sound close but belong to a sibling skill or to no skill"]
  },
  "tasks": [{
    "id": "short-id",
    "fixture": "fixtures/short-id",
    "prompt": "the request as a user would type it; never names the skill",
    "check": "shell command run in the project folder after the agent finishes; exit 0 = pass. $CASE_DIR is this cases folder (for hidden/ files).",
    "rubric": ["3–5 process criteria a judge can see in the transcript, e.g. 'reproduced the failure before editing'"],
    "max_steps": 40
  }]
}
```

Rules for a good task test:
- It has a **trap** the skill's guidance avoids and a capable agent without it plausibly falls into (an obvious but
  wrong fix, a decoy, a tempting shortcut such as skipping a test). Otherwise baseline and skill tie and we learn
  nothing.
- The check is **objective and hidden**: hidden tests, mutants, exact answers; never "a file exists".
- The check **fails on the untouched fixture and passes on the reference** (`python3 eval/validate_case.py <skill>`
  proves both).
- No network; Python 3 stdlib, Node 18, git, sqlite3, bash are available. Keep fixtures small (a few files, under
  ~300 lines total) so small models can do them.
- The prompt reads like a real user, works without follow-up questions, and asks for the result in a file when the
  answer is text (e.g. "write your findings to REVIEW.md").
- Fixtures contain no skill files and nothing that names the skill.

Trigger near misses should mostly be requests a sibling skill owns (e.g. for `fix-flaky-tests`: "this test always
fails since yesterday's merge" belongs to `bisect-regression` or `systematic-debugging`), plus one plain request no
skill needs ("what does this function return?").
