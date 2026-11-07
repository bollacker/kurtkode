# Final taxonomy of software-development skills

Assembled 2026-10-25 after research, writing and testing (`RESULTS.md`). It replaces `TAXONOMY_v1.md`. Three
tiers, as planned: **30 core skills** in `skills/` (written and tested here), **routed packs** from vendors
(`packs/INDEX.md`), and work that is **better done by the harness** than by a skill. Plus one install step that
the tests showed matters as much as any skill: the **AGENTS.md snippet**.

Status column: **proven** = beat the no-skill baseline and the irrelevant-skill control on its task;
**ceiling** = the model already passed the task without it (the skill raised process scores, not the pass rate);
**limit** = helps when loaded but a model habit survives it, or it rarely gets chosen; see notes.
Kinds: P process, K knowledge, T tool (ships a script with exit codes). "v0" = items of the first taxonomy covered.

## 1. Core library (30 skills)

### Understand the code

| Skill | Kind | v0 | What it does | Status |
|---|---|---|---|---|
| `navigate-code` | P | 1, 2, 4 | Orient in a repo, trace a value or request end to end, find what a change affects; every claim cites file:line | ceiling |
| `code-history` | T | 3 | Why code is the way it is: the line's history across renames and restyles, the origin commit and its reason (`line_history.py`) | ceiling |

### Decide and plan

| Skill | Kind | v0 | What it does | Status |
|---|---|---|---|---|
| `clarify-requirements` | P | 6, 7, 71 | Turn a vague or risky request into acceptance criteria; ask if someone can answer, else take the reversible reading and record it | proven when loaded; limit: in the library arm the model picked implement-change instead |
| `plan-work` | P | 8, 11 | Small steps each with a check, kept as a ledger; decision records | ceiling (revised: tick as you go) |

### Build

| Skill | Kind | v0 | What it does | Status |
|---|---|---|---|---|
| `implement-change` | P | 12, 5 | The change loop: read, find the house helper, baseline, small verified steps, installed-version docs, no destructive surprises | ceiling |
| `test-driven-development` | P | 13 | Red, green, refactor; each behavior seen failing first | proven (1/3 → 3/3) |
| `refactor-safely` | P | 14, 64 | Pin behavior (characterization tests or old/new comparison), then small green moves | ceiling |
| `codemod` | T | 65 | One mechanical change across many files: classified inventory, reviewed selection, dry run, one-pass apply (`codemod.py`) | proven (0/3 → 3/3) |
| `error-handling` | K | 15 | No swallowed errors or silent defaults; specific, located errors at boundaries | ceiling |
| `concurrency` | K/P | 16, 37 | Races, lost updates, deadlocks, missing awaits: reproduce under stress, make it atomic, lock order | ceiling |
| `regex` | T | 21 | Write and test a pattern on matching and non-matching examples; flavor differences (`regex_test.py`) | ceiling |
| `shell-scripts` | K | 19 | Strict, quoted, safe scripts and small CLIs | proven, small (2/3 → 3/3) |

### Test and verify

| Skill | Kind | v0 | What it does | Status |
|---|---|---|---|---|
| `write-tests` | P/T | 22, 26 | Tests that catch real bugs, measured by mutation (`mutate.py`) | ceiling |
| `fix-flaky-tests` | T | 24 | Prove the flake by repetition, classify, find the polluter, fix the cause (`repeat.py`, `find_polluter.py`) | ceiling |
| `verify-before-done` | P/T | 30, 77 | Fresh evidence per claim from the project's full check (`find_checks.py`); a not-verified list | limit: finds the failure, but Flash still weakened the test 2 of 3 times |

### Debug

| Skill | Kind | v0 | What it does | Status |
|---|---|---|---|---|
| `systematic-debugging` | P | 31, 32, 34 | Reproduce, isolate, root cause, fix there, prove; diagnostics reference for 7 languages | ceiling |
| `bisect-regression` | T | 33 | Find the breaking commit with a safe `git bisect run` wrapper that skips unbuildable commits (`bisect_run.py`) | ceiling |
| `performance` | T | 35, 36, 67 | Measure, profile, fix the hot spot, compare outputs and timings (`bench.py`, `cpuprofile_top.py`) | ceiling |

### Review and security

| Skill | Kind | v0 | What it does | Status |
|---|---|---|---|---|
| `code-review` | P/T | 28 | Review a diff for real bugs, each finding checked before it's reported (`changed_lines.py`) | ceiling |
| `respond-to-review` | P | 29 | Check each comment against the code; apply the right ones, decline wrong ones with evidence | proven (0/3 → 3/3) |
| `security-review` | P/T | 38, 39, 41 | Exploitable issues with an attack path each, few false alarms; secrets scan that never prints values (`secret_scan.py`) | proven on the leaked key (0/3 → 3/3); the code-audit task mostly measured Flash refusing |

### Data, dependencies, build, release

| Skill | Kind | v0 | What it does | Status |
|---|---|---|---|---|
| `database-migrations` | P/K | 43 | Reversible migrations that keep data; engine notes (SQLite rebuilds, Postgres locks) | ceiling |
| `upgrade-dependencies` | P | 46, 40 | One dependency at a time, every breaking change including silent ones, audits | ceiling |
| `fix-build-and-ci` | T | 47, 54 | First real error in a long log (`first_error.py`), reproduce, fix the cause, never weaken the check | ceiling |
| `release` | T | 48, 53 | Version consistent everywhere (`find_versions.py`), changelog of user-facing changes, tag | gain not attributable (control also passed) |

### Version control

| Skill | Kind | v0 | What it does | Status |
|---|---|---|---|---|
| `commit-and-pr` | P/T | 50, 52 | Focused commits, no secrets or debug files (`check_staged.py`), PR text with how it was verified | proven (0/3 → 3/3) |
| `resolve-merge-conflicts` | T | 51 | Keep both sides' intent, including stale names in cleanly merged files (`conflict_context.py`) | ceiling |

### Documentation and agent practice

| Skill | Kind | v0 | What it does | Status |
|---|---|---|---|---|
| `write-docs` | P/T | 60–63 | READMEs, API docs and comments whose commands were run (`check_doc_commands.py`) | proven, small (2/3 → 3/3) |
| `handoff-notes` | P | 74, 72 | HANDOFF.md a fresh session can resume from, with CI's real verify command | no clear gain: 3/3 in both arms after revision, but the control also passed 2/2 |
| `write-skills` | P/T | 76 | Write and test a portable skill: trigger description, short body, cases with near misses (`validate_skill.py`) | proven, small (2/3 → 3/3) |

### Install step: the AGENTS.md snippet

In kurtkode this is built in: the 30 skills ship with it and the system prompt carries the same instruction
(Flash recall 90% with nothing installed). For other agents, `install/AGENTS-snippet.md`: four lines in the
project's AGENTS.md telling the agent to check the skill list before starting. It raised Flash's trigger recall from 66% to 92% with no wrong loads, which is a larger effect than any
single skill. It barely moves a 9B local model (4% → 11%): for small models the harness should pick the skill.

## 2. Routed packs (unchanged from v1)

Vendor-maintained knowledge, added per project from `packs/INDEX.md` rather than copied: React/Next.js and web UI
(Vercel), Postgres (Supabase), Terraform (HashiCorp), Python/C++ toolchains, fuzzing, SAST and supply chain (Trail of
Bits), SwiftUI (twostraws), browser testing and UI from design (Anthropic), GitHub Actions with `gh` (OpenAI),
cloud platforms (their vendors), git worktrees (superpowers). Not tested here.

## 3. Better done by the harness

| Need | Where it belongs | Why |
|---|---|---|
| Destructive-action guardrails | permission rules, danger checks, hooks (kurtkode has them) | a skill is advice; a hook is enforced |
| Context management, delegation | the system prompt and loop (kurtkode's `delegation.md`) | needed on every turn, so always loaded |
| Choosing the skill for small models | kurtkode's skill router (built): one short question to the model, then the skill's instructions in a note | Qwen 3.5 9B loaded the right skill 4–11% of the time on its own, 94% with the router; tasks 6% → 32% |
| Low-value as generic skills | API design, auth, ETL, dev environments, containers, observability, incidents, tech debt, CSS (v0 items 9, 42, 45, 49, 55, 57, 59, 66, 70) | models know the basics; vendor packs cover the specifics |

## 4. Evidence per skill

| skill | case | Flash none | Flash control | Flash library | Flash forced | Argon none | Argon library | Qwen none | Qwen forced | recall (snippet) | recall (none) | Qwen recall | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bisect-regression | cents-regression | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 7/7 | 5/7 | 4/7 | ceiling |
| clarify-requirements | close-accounts | 0/3 | 0/2 | 0/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 6/7 | 2/7 | helps (r3) |
| code-history | why-page-size | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 1/1 | 7/7 | 6/7 | 0/7 | ceiling |
| code-review | bulk-discounts | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 7/7 | 7/7 | 2/7 | ceiling |
| codemod | rename-fetch-user | 0/3 | 0/2 | 1/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 7/7 | 4/7 | 1/7 | helps (r2) |
| commit-and-pr | two-changes | 0/3 | 0/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 7/7 | 6/7 | 2/7 | helps |
| concurrency | oversell | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 1/1 | 6/7 | 3/7 | 1/7 | ceiling |
| database-migrations | order-currency | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 7/7 | 7/7 | 0/7 | ceiling |
| error-handling | silent-config | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 6/7 | 0/7 | ceiling |
| fix-build-and-ci | red-pipeline | 3/3 | 2/2 | 3/3 | 2/3 | 1/1 | 1/1 | 0/1 | 1/1 | 7/7 | 4/7 | 1/7 | ceiling |
| fix-flaky-tests | order-dependent | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 1/1 | 1/1 | 6/6 | 4/6 | 0/6 | ceiling |
| handoff-notes | half-done-median | 2/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 1/1 | 7/7 | 7/7 | 2/7 | no clear effect (r2) |
| implement-change | invoice-discount | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 1/7 | 0/7 | ceiling (r3) |
| navigate-code | export-timeout | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 3/7 | 0/7 | ceiling |
| performance | slow-summary | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 4/7 | 0/7 | ceiling |
| plan-work | note-tags | 2/3 | 2/2 | 3/3 | 2/3 | 1/1 | 1/1 | 0/1 | 0/1 | 5/7 | 5/7 | 0/7 | no clear effect (r2) |
| refactor-safely | tangled-invoice | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 2/7 | 0/7 | ceiling |
| regex | access-log | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 4/7 | 0/7 | ceiling |
| release | next-release | 0/3 | 2/2 | 2/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 7/7 | 7/7 | 4/7 | no clear effect |
| resolve-merge-conflicts | grams-vs-express | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 7/7 | 6/7 | 1/7 | ceiling |
| respond-to-review | retry-review | 0/3 | 0/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 7/7 | 6/7 | 2/7 | helps |
| security-review | leaked-key | 0/3 | 0/2 | 3/3 | 3/3 | 0/1 | 1/1 | 0/1 | 1/1 | 6/7 | 3/7 | 2/7 | helps |
| security-review | user-service | 0/3 | 0/2 | 1/3 | 0/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 3/7 | 2/7 | helps a little |
| shell-scripts | fragile-packager | 2/3 | 1/2 | 2/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 4/7 | 0/7 | helps a little |
| systematic-debugging | missing-vat | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 1/1 | 5/7 | 3/7 | 0/7 | ceiling |
| test-driven-development | split-bill | 1/3 | 1/2 | 2/3 | 3/3 | 0/1 | 1/1 | 0/1 | 0/1 | 5/7 | 4/7 | 0/7 | helps a little |
| upgrade-dependencies | textkit-v2 | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 0/1 | 7/7 | 2/7 | 0/7 | ceiling |
| verify-before-done | unicode-slugs | 0/3 | 0/2 | 0/3 | 1/3 | 1/1 | 1/1 | 0/1 | 0/1 | 6/7 | 7/7 | 0/7 | helps a little (r3) |
| write-docs | tally-cli | 2/3 | 1/2 | 3/3 | 3/3 | 1/1 | 1/1 | 0/1 | 1/1 | 7/7 | 2/7 | 0/7 | helps a little |
| write-skills | migration-skill | 2/3 | 1/2 | 3/3 | 3/3 | 0/1 | 1/1 | 0/1 | 0/1 | 7/7 | 6/7 | 0/7 | helps a little |
| write-tests | durations | 3/3 | 2/2 | 3/3 | 3/3 | 1/1 | 1/1 | 1/1 | 1/1 | 7/7 | 4/7 | 0/7 | ceiling |
| ALL |  | 62/93 | 44/62 | 80/93 | 86/93 | 28/31 | 31/31 | 2/31 | 9/31 | 192/209 | 138/209 | 24/209 | ceiling=17 helps a little=6 helps=5 no clear effect=3 |

Flash columns: 3 trials (control 2); "library" and "forced" use the latest version of revised skills (r2/r3 in the
verdict). Argon and Qwen: 1 trial. Recall: should-requests that loaded the skill, Flash with and without the
snippet, and Qwen with the snippet.

## 5. Next candidates

- A second, independently written task per skill, so ceiling skills can show (or fail to show) a gain on harder
  fixtures, and so no skill is judged only on a task written beside it.
- Head-to-head runs against the published skills we learned from (superpowers is MIT) on the same tasks.
- Second-tier skills from section 3 if real sessions show a need (containers and observability are the likeliest).
