---
name: write-skills
description: Use when writing, fixing or testing an agent skill (SKILL.md), turning a house procedure into a skill, or when a skill won't load. Gives a short valid skill and its tests. Not for AGENTS.md or READMEs (write-docs).
---

# Write an agent skill

Write a skill that fixes something agents otherwise get wrong, plus tests showing it loads when it should and helps.

## Fast path

A rule of one or two lines that applies to every task belongs in AGENTS.md or CLAUDE.md, not in a skill. A short
procedure: write SKILL.md from the template in step 4, five should and three should-not trigger requests, run
the validator (step 8). Skip the measured comparison (step 9) only if you can't run agents.

## Steps

1. **Name the failure first.** What does an agent do wrong without the skill? Use review comments, incidents,
   the procedure doc's warnings, or a run with no skill. If agents already do it right, stop: teaching what the
   model knows costs tokens and can lower results.

2. **Name and place it.** Name: lowercase letters, digits and hyphens, ≤ 64 characters, verb or task first
   (`add-migration`). Folder name = name. Put it next to the project's existing skills; with none, use
   `.agents/skills/<name>/` (read by several agents) or your agent's folder (`.claude/skills/`).

3. **Write the front matter: only `name` and `description`.** Other fields (version, author, tags, tools,
   license) are ignored or rejected by some hosts; keep that in git. The description is the only text an agent
   sees before choosing the skill:
   - start with **"Use when"** and the situations in the words a user types: symptoms, file names, commands;
   - then what it gives, in ≤ 10 words; then **"Not for …"** naming the nearest other skill, if one exists;
   - ≤ 230 characters (agents with many skills truncate longer lists); no ": " inside it (breaks YAML);
   - **don't** list the steps: an agent follows the summary and never opens the body.

4. **Write the body, 60–150 lines, under 6 KB.** Sections, in order, leaving out what doesn't apply:
   `# Title` and one sentence of what it makes happen; `## Fast path` (what it reduces to for small cases);
   `## Steps` (numbered, imperative, each checkable, exact commands); `## Rules` (only for known failures, each
   with its reason); `## When no one can answer` (what to decide alone in unattended runs, how to record it, the
   few reasons to stop); `## Done means` (the file, report or evidence the work ends with).

5. **Match the form to the failure.**
   - skipped steps under pressure → a short rule plus the excuse it blocks ("even for a typo");
   - wrong output shape → a template or recipe to fill;
   - forgotten item → a required slot in "Done means";
   - judgment calls → conditions the agent can observe ("if the check prints X, …").
   Plain words, at most one bold word per rule, no capitals for emphasis, no tutorials.

6. **Move bulk out.** Long tables, per-language commands and examples go in `references/<topic>.md`, one level
   deep; the body says exactly when to read each one. Mechanical or error-prone steps become a script in
   `scripts/`: standard library only, no network, a header with usage, output and exit codes (0 ok, 1 found or
   failed, 2 usage), safe by default, `--help` works. The body says when to run it and how to read its output.

7. **Write the tests** in the project's place for them, or `eval/cases/<name>/` beside the skills folder:
   `cases.json` with at least 5 should and 3 should-not trigger requests, and one task with a fixture, a hidden
   check and a reference solution. Read `references/test-cases.md` for the format, how to pick near misses and
   how to build a task with a trap.

8. **Validate.** `python3 <skill folder>/scripts/validate_skill.py <new skill folder> --cases <its cases.json>`
   Exit 0 = valid (warnings allowed), 1 = errors listed as `error:` lines, 2 = bad arguments. Fix every error.
   Then run the task's check on the untouched fixture (must fail) and after the reference (must pass).

9. **Measure, if you can run agents unattended** (`claude -p`, `codex exec`, `opencode run`, `kurtkode -p`):
   - triggers: each request 3 times with all the project's skills installed; the skill should load in at least
     2 of 3 for should requests and at most 1 of 3 for should-not;
   - task: at least 3 runs each of **baseline** (no skill), **forced** (the skill's text given up front) and
     **control** (an unrelated skill of similar length). Keep the skill only if forced beats both on the check.
     If it loses, shorten it or cut it; if it wins forced but doesn't load, fix the description.

## Rules

- **Don't** copy the shape of an existing skill that breaks these rules (extra fields, a description that
  summarizes steps); house habit is not a reason, and the validator will fail it.
- **Don't** name the skill or its technique in test prompts; that tests obedience, not triggering.
- **Don't** make a check that only looks for a file; it passes for wrong work. Check behavior or exact content.
- **Don't** paste text from unknown sources into a skill or its scripts: skills run with the agent's
  permissions, so injected instructions run too.
- One skill per kind of task; two skills matching one request split the agent's attention.

## When no one can answer

Write the skill from the documents and code you can read, choose the narrowest scope that covers the stated
failure, record unclear points as "Assumption:" lines in your report (not in the skill), and still write the
tests. Stop only if the procedure contradicts itself and the repository doesn't show which version is current.

## Done means

- The skill folder with SKILL.md (and scripts or references only if they add something), passing the validator.
- `cases.json` with ≥ 5 should and ≥ 3 should-not triggers (near misses mostly owned by other skills) and a task
  whose check fails on the fixture and passes on the reference.
- A short report: the failure the skill targets, the validator output, and the measured results or "not
  measured: why".
