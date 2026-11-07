# Testing the skills: method and results

Run 2026-10-25 with the kurtkode CLI on three models: **Gemini 3.6 Flash** (main model), **Gemini 4 Argon**
(a stronger model) and **Qwen 3.5 9B** on a LAN LM Studio (a small local model). Cost at list price: $101
($71 task runs, $20 trigger runs, $10 judging); the Qwen runs were free.

## Method

Each skill was tested in two ways (`eval/skilleval.py`):

- **Triggering.** About 12 requests per skill (360 in all): 6–7 that should load it, worded as users write
  (rarely naming the technique), and 4–6 near misses, mostly requests a sibling skill owns ("this test has failed
  on every run since the merge" is bisect's or debugging's, not flaky-tests'). Each runs read-only for up to 8 steps
  in a small neutral project with **all 30 skills installed**. Recall = should-requests that loaded the skill;
  precision = near misses that did *not* load it.
- **Tasks.** One task per skill (two for security-review), 31 in all: a small fixture project with a trap that the
  skill's guidance avoids and that an agent without it plausibly falls into (an obvious but wrong fix, a decoy, a
  shortcut that hides a failure). A **hidden check** decides pass or fail (hidden tests, seeded mutants, exact answers);
  each check was proven to fail on the untouched fixture and pass on a reference solution (`validate_case.py`).
  A judge model (Gemini 4 Argon) also scored 3–5 process criteria from the transcript (the "rubric").
  Four arms, three trials each on Flash:
  - **none**: no skills installed (the baseline);
  - **control**: one irrelevant skill of similar length (meeting-notes conventions), force-loaded: what merely
    loading a skill costs or gains;
  - **library**: all 30 skills installed plus the AGENTS.md snippet; the model decides what to load;
  - **forced**: the run is told to load this skill: the content's effect without the triggering question.

## Results

### Triggering

| Setup | Recall (right skill loaded) | Near misses loading this skill |
|---|---|---|
| Flash, 3 steps | 107/209 (51%) | 0/151 |
| Flash, 8 steps | 138/209 (66%) | 0/151 |
| **Flash, 8 steps, AGENTS.md snippet** | **192/209 (92%)** | **0/151** |
| Qwen 3.5 9B, 8 steps | 9/209 (4%) | 0/151 |
| Qwen 3.5 9B, 8 steps, snippet | 24/209 (11%) | 0/151 |

- Descriptions never caused a wrong load: no near miss loaded the skill it was written against, in any setup. With
  the snippet, 119 of 151 near misses loaded *a* skill, and reading them, nearly all loaded the sibling they belong
  to; plain questions ("What is semantic versioning?") loaded none. Errors: two security-audit requests and one
  "failing since the merge" request loaded nothing, and "add a line to AGENTS.md" loaded implement-change.
- Without the snippet, models start exploring (`glob`, `grep`, `list_dir`) and often never come back to the skill
  list. With it, the skill was the **first** call in 176 of 192 hits.
- **The small model hardly uses skills at all**, even when told to. For models like it, the harness should choose
  the skill (by retrieval or a router) rather than leave it to the model.

**Built into kurtkode** (later the same day): the skills now ship with kurtkode and its system prompt carries the
snippet's instruction (`Prompts/skills.md`). Measured with nothing installed in the project:

| Setup | Recall | Near misses loading this skill |
|---|---|---|
| Flash, kurtkode default | 189/209 (90%); 181/199 (91%) without the 10 runs the network dropped | 0/151 |
| Qwen 3.5 9B, kurtkode default | 21/209 (10%) | 0/151 |

The same as the AGENTS.md snippet (92% and 11%).

**A skill router for small models** (also built that day, `SkillRouter` in kurtkode): before a run, the session's
own model is asked one short question (no tools, no thinking) — which skill fits this request, or none — and the
chosen skill's instructions go in a note after the user's message. Auto: on for OpenAI-compatible servers (LM Studio,
OpenRouter), off for Claude and Gemini.

| Router variant on Qwen 3.5 9B | Recall | Wrong own-skill loads on near misses | Tasks passed |
|---|---|---|---|
| none (model decides) | 21/209 (10%) | 0/151 | 2/31 (6%) |
| question only, offline (`router_experiment.py`) | 198/209 (95%), 1.6 s each | 2/151 | – |
| note saying "load X" | 182/209 (87%): the model ignored the note in 19 runs | 1/151 | – |
| **note carrying the skill's instructions** (shipped) | **196/209 (94%)** | 2/151 | **10/31 (32%)** |
| skill forced, for comparison | – | – | 9/31 (29%) |

A keyword (BM25) router scored at best 128/209 with many wrong picks: the model's own judgment is needed.
Cost per routed request on Qwen 3.5 9B: the question takes about 1.6 s, and the note (~1,200 tokens of instructions)
adds about 1 s to the agent's first reply. A local server's prompt cache survived it: in two-turn sessions
(`cache_check.py`, 3 trials each), turn 2's first agent request started after 0.7–1.1 s with the router off and
1.8–2.3 s with it on; losing the cache would have meant re-reading the whole session. bang's slot count is unknown;
a server with a single slot may behave differently. The cost: about 1,950 tokens more in every request that offers
tools (the skill list in the tool's description, ~1,880, and the prompt line, ~70); cached on paid APIs, but a
quarter of an 8k local context.

### Tasks

Gemini 3.6 Flash, 31 tasks, pass counts (latest version of each revised skill):

| Arm | Pass | Rubric | Cost per run | Tool calls |
|---|---|---|---|---|
| none | 62/93 (67%) | 75% | $0.129 | 23 |
| control (irrelevant skill) | 44/62 (71%) | 75% | $0.129 | 23 |
| library (model chooses) | 80/93 (86%) | 91% | $0.149 | 27 |
| forced (skill loaded) | 86/93 (92%) | 93% | $0.152 | 27 |

Gemini 4 Argon, one trial each: none 28/31 (90%), rubric 84%, $0.113 → library 31/31 (100%), rubric 100%, $0.164.

Qwen 3.5 9B, one trial each: none 2/31 (6%) → forced 9/31 (29%). The skill content helps a small model a lot when it is loaded (code-history, concurrency, fix-build-and-ci, handoff-notes, security-review, systematic-debugging, write-docs went from fail to pass), but the model rarely loads a skill by itself (see Triggering), and most tasks remain beyond it (step limits, garbled edits).

- **The right skill helps; any skill doesn't.** The control arm (an irrelevant skill of the same size) moved Flash
  from 67% to 71%, within noise; the right skill, loaded, moved it to 92%. So the gain is the content, not the
  extra context or the act of loading.
- **Where skills help most** (Flash, none → forced): codemod 0/3 → 3/3, commit-and-pr 0/3 → 3/3, respond-to-review
  0/3 → 3/3, security-review (leaked key) 0/3 → 3/3, clarify-requirements 0/3 → 3/3, test-driven-development
  1/3 → 3/3. These are the discipline traps: committing a stray `.env`, applying a wrong review comment, deleting
  what a cascade destroys, a sed rename hitting decoys, tests that miss the rounding rule. (release went 0/3 → 3/3
  too, but its control arm passed 2/2, so that gain can't be credited to the skill.)
- **Ceiling cases**: 17 tasks were already passed by Flash without skills (bisect, debugging, concurrency,
  migrations, …). There the skills still raised the process scores (e.g. bisect rubric 83 → 100) at some extra
  cost, but the check can't show a pass-rate gain. Harder fixtures, or the small model, are where to look next.
- **Cost**: skills add 15–45% per run (more reading, more verification steps). On Argon, the cost rose 45% for a
  3-task gain.

### What the tests changed

Testing found problems in both the skills and the tests:

| Found | Fix | Effect (Flash) |
|---|---|---|
| Trigger recall only 51–66% | `install/AGENTS-snippet.md` (4 lines naming the skills in AGENTS.md) | recall 92% |
| 7 descriptions broke strict YAML (`: `) or didn't start with the trigger | reworded; the write-skills validator now checks it | portable to Claude Code |
| handoff-notes: agents ran plain unittest, missed CI's real check | the fast path now says to find CI's command | forced 2/3 → 3/3, library 1/3 → 3/3 |
| clarify-requirements: archived users still listed | "make the reading hold everywhere the data is read" | forced 0/3 → 3/3 |
| codemod: in the library arm, agents edited 12 files by hand and ran out of steps | a rule to apply the reviewed selection with the script | library 0/3 → 1/3 (forced stayed 3/3) |
| plan-work: runs ended with unticked steps | tick each step when its check passes; 3–6 steps | library 2/3 → 3/3 |
| verify-before-done: agents found the failing test and then weakened it | a rule, then the same guidance moved into the steps | forced 0/3 → 1/3 (a second run fixed it but ran out of steps) |
| implement-change (loaded instead of clarify-requirements): agents saw the cascade and hard-deleted anyway | a step on destructive changes | library still 0/3: the judge saw agents read the step and do it anyway |
| 4 hidden checks rejected good work (a stricter-but-right test, an error message, a documented exit code, a correct warning about a stale path) | checks fixed; old runs re-scored from their kept folders | 3 "no effect"/"hurts" verdicts became "helps" or "ceiling" |

Two lessons from that table:

- **Rules sections are skimmed; steps are followed.** The same guidance worked better as part of a step than as a
  "Don't" rule. And some habits of a given model (weakening a test that blocks it, deleting what was asked to be
  deleted) survive even an explicit step: skills move behavior, they don't guarantee it.
- **A check that passes its reference can still be wrong.** All four broken checks passed `validate_case.py`;
  they failed real agents that did better than the reference anticipated. Reading the failures of "every arm fails"
  and "skill hurts" cases found all four.

### Limits

- Three trials per arm on Flash (one on Argon and Qwen): a single run moves a cell by 33%. Totals across 31 tasks
  are more trustworthy than any one row.
- One task per skill, written by us alongside the skill. Some skill text sits close to its own task's trap (noted by
  the writers; the closest examples were removed). The gains on the "discipline" tasks are the most likely to
  transfer; a second, independently written task per skill would tell.
- Argon judged its own runs in the Argon comparison.
- Gemini 3.6 Flash refused to do the user-service security review in every no-skill and forced run ("I cannot
  perform vulnerability analysis"); the library arm got past the refusal once in three. That task measures refusals
  more than the skill.
- The trigger project is small and doesn't contain the files the requests mention, which pushes models to search
  instead of loading a skill; real projects may trigger differently.

## Files

`eval/results/`: `trigger-*.jsonl` (per request: loaded skills, first tool calls), `task-*.jsonl` (per run: pass,
check output, rubric scores and notes, cost, tool calls), `superseded-*` (runs set aside when a check was fixed).
`eval/summarize.py` prints the per-skill table in `TAXONOMY_FINAL.md`; `eval/analyze.py` compares arms.
