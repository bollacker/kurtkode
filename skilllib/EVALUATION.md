# Existing skills: evaluation, gaps, and what to change

Written 2026-10-25 from the research report (`reports/Software development agent skills.md`) and its notes
(`research_notes/Software development agent skills/`). Verdicts there rest on reading the skills, not running them;
our own runs (the test steps) are the first outcome-level measurements.

## What the evidence says about skills in general

| Finding | Source | Consequence for this library |
|---|---|---|
| Curated skills: +4.5 points on software-engineering tasks (smallest domain gain); 16 of 84 tasks got worse; "comprehensive" skills −2.9 | SkillsBench, arXiv 2602.12670 | Short, focused skills; a skill must earn its tokens on a test, or go |
| 1–3 skills per task +18 points; 4+ only +5.9 | SkillsBench | One skill per kind of task; skills don't chain long pipelines |
| Web-dev skills cut Pass@2 1.3–4.2%, cost +72–394%; an irrelevant skill of the same length explains much of it | WebDev-Skills-Bench, arXiv 2608.23067 | Every task test has a length-matched irrelevant-skill control arm |
| A knowledge skill was never invoked in 56% of runs; an explicit pointer fixed it | Vercel, Jan 2026 | Measure triggering separately (trigger tests, forced arm); route knowledge packs by an index |
| Selection accuracy falls as libraries grow (above 90% at ≤20 skills; collapses toward 200), earlier for small models | arXiv 2601.04748, 2607.01874 (snippets) | About 30 visible skills; selection measured with the whole library installed, on a small local model too |
| Codex caps the skill list at 8,000 characters | OpenAI docs | Descriptions ≤ 230 characters each (30 × 230 ≈ 7k) |
| Prompt injection through skills: up to 80% success; 13% of marketplace skills had critical issues | SkillInject; Snyk | Write our own text; every bundled script is ours and read |
| "Match the form to the failure": prohibitions for discipline failures, positive recipes for output shape | superpowers micro-tests (5 reps) | The style guide adopts it |

## Existing skills, by kind

**Process skills.** obra/superpowers (MIT) is the best source: systematic-debugging, test-driven-development,
verification-before-completion, receiving-code-review, writing-plans/executing-plans, using-git-worktrees. Strengths:
named failure modes, hard gates, rationalization tables, 3–10 KB. Weaknesses that matter for kurtkode:

1. No proportionality: a one-line fix gets the full four-phase gate.
2. No autonomous path: "ask your human partner" dead-ends in `-p` runs, subagents and Full Auto.
3. TypeScript-only examples; coupled to superpowers' own paths and scripts (plans).
4. Long for small local models (systematic-debugging plus its references is far past what a 9B model follows).

Anthropic's `/code-review` and `/security-review` have the best review designs (every finding re-checked; explicit
false-positive exclusions; exploit scenario per security finding), but they are slash commands built on subagents and
`gh`, not portable skills. Trail of Bits (CC-BY-SA-4.0) is the deepest for security, fuzzing and static analysis;
share-alike makes it something to route to, not copy from.

**Knowledge skills.** Good where a vendor maintains rules the model lacks (Vercel React, Supabase Postgres, HashiCorp
Terraform, ToB modern-python/modern-cpp, swiftui-pro). Generic language "expert" skills (wshobson, ECC, Jeffallan)
restate what models already know; registry reviews and the benchmarks agree they don't pay. Decision: **don't write
language or framework packs**; route to vendor packs from an index (`packs/INDEX.md`).

**Tool skills.** Good ones ship a script with an exit contract (OpenAI gh-fix-ci, Anthropic webapp-testing, ToB
supply-chain auditor). This is where nothing exists for: bisecting, history archaeology, codemods, flaky tests, build
debugging, profiling.

## Gaps (what is missing or weak)

| Gap | Taxonomy v0 items | Kind |
|---|---|---|
| Nothing at all | 3 history archaeology, 21 regex, 65 codemods | Tool |
| Buried inside other skills, hard to trigger | 24 flaky tests, 32 root cause, 26 coverage gaps | Process/Tool |
| Named skills exist, none good | 14/64 refactoring with characterization tests, 15 error handling, 19 scripts/CLIs, 33 bisect, 35–37 performance, memory, concurrency, 43 migrations, 46 upgrades, 47 build debugging, 48/53 release, 50/52 commits and PRs, 51 merge conflicts, 60–63 docs | Process/Tool |
| Good, but needs changes for kurtkode | 6/7/71 clarify (autonomous mode), 11/12 planning (decouple), 13 TDD (fast path, legacy path), 28 review (portable, verify findings), 29 receiving review, 30 verification, 31 debugging, 38 security review | Process |
| Good, adopt from the vendor by routing | 10/20/44 Postgres, 17 Python/C++/Swift, 18 frameworks, 23/69 webapp testing and UI, 25 fuzzing, 27 SAST, 40 supply chain, 54 GitHub Actions CI, 58 Terraform, 68 accessibility | Knowledge |
| Better as harness features than skills | destructive-action guardrails (kurtkode has rules and danger checks), 72 context management, 73 delegation (kurtkode's `delegation.md` prompt) | — |

## Improvements every adapted skill gets

1. **A fast path**: when the task is small and the cause or change is obvious, say what the skill reduces to.
2. **An autonomous rule**: when no one can answer (`-p`, subagent, Full Auto), make the safest reasonable choice,
   record it as an assumption, and continue; stop only for the listed reasons.
3. **Language-neutral**, with commands for several stacks where commands matter.
4. **Short**: a body most small models can follow (target ≤ 150 lines; details in `references/`).
5. **An output contract**: what the skill's work ends with (a file, a report shape, evidence).
6. **Tested**: trigger cases with near misses, a task with a check, run against baseline, forced and control arms.

## Decision on reuse

We write our own text for every skill, crediting the designs we learned from (README "Sources"). Reasons: the
improvements above change most of each skill anyway; it avoids share-alike obligations (ToB) and unverified licenses;
and it keeps every line of skill text and script reviewed (the injection risk). Running the published originals
head-to-head against ours (superpowers is MIT) is left as a follow-up that needs the user's go-ahead to fetch them.
