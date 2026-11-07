# Target taxonomy v1: the skills to build

Written 2026-10-25 from `TAXONOMY_v0.md` (77 items), the research report and `EVALUATION.md`. Three tiers:

1. **Core library** (`skills/`): 30 skills we write and test. Installed together; their descriptions fit Codex's
   8,000-character list budget (≤ 230 characters each).
2. **Routed packs** (`packs/INDEX.md`): vendor knowledge we don't copy; an index tells the agent when to fetch or
   install which pack.
3. **Not skills**: things that belong in the harness (hooks, rules, the system prompt) or aren't worth a skill.

Kinds: P process, K knowledge, T tool (ships a script with an exit contract). "v0" lists the items each skill covers.
Origin: **A** adapted design (ideas from a published skill, our own text), **N** new (nothing good exists).

## 1. Core library (30)

| # | Skill | Kind | v0 items | Origin | What it is for | Task test idea (fixture → check) |
|---|---|---|---|---|---|---|
| **Understand** |
| 1 | `navigate-code` | P | 1, 2, 4 | A (ToB audit-context, Anthropic code-explorer) | Get oriented in a repo, trace a behavior end to end, find what a change affects; every claim cites file:line | A repo where a value flows through 4 modules with a decoy path → the answer names the right final value |
| 2 | `code-history` | T | 3 | N | Why code is the way it is: `log -S/-G/-L`, `blame -w -C -C`, follow renames, read the commit and its tests | A repo whose odd constant is explained only in an old commit message, after a rename → the answer cites the reason |
| **Decide and plan** |
| 3 | `clarify-requirements` | P | 6, 7, 71 | A (superpowers brainstorming, grill-me) | Turn a vague request into acceptance criteria; ask when someone can answer, else choose defaults and record them | Ambiguous request in a `-p` run → assumptions recorded, the safe reading built |
| 4 | `plan-work` | P | 8, 11 | A (superpowers writing-plans) | A plan of small verifiable steps with checkpoints, kept as a progress ledger; ADR template for design choices | Multi-part feature → PLAN.md with steps, a verify per step, then done in order |
| **Build** |
| 5 | `implement-change` | P | 12, 5 | A (superpowers executing-plans, feature-dev) | The change loop: read first, smallest step, verify each, match house style, ground new APIs in the installed version's docs | Feature in a repo with a house helper → uses the helper; hidden tests pass |
| 6 | `test-driven-development` | P | 13 | A (superpowers TDD) | Red, green, refactor; watch each test fail for the right reason; fast path; legacy path | Feature with TDD asked → tests catch seeded mutants |
| 7 | `refactor-safely` | P | 14, 64 | A (igmarin refactor-code) | Behavior-preserving change: characterization tests first, one move at a time, tests green between moves | Untested tangled function → hidden behavior tests still pass, structure changed |
| 8 | `codemod` | T | 65 | N | Mechanical change across many files: inventory, script it, dry run, apply, verify; leave look-alikes alone | Rename an API in 30 files with decoys (same name in strings, another module) → exact set changed |
| 9 | `error-handling` | K | 15 | N | No swallowed errors or silent fallbacks; fail loudly at boundaries; errors that say what and where | Code that swallows errors → hidden tests expect specific errors raised |
| 10 | `concurrency` | K/P | 16, 37 | N | Races, deadlocks, async pitfalls; how to reproduce and fix them | A counter with a race under threads → hidden stress test passes |
| 11 | `regex` | T | 21 | N | Write and test a pattern against positive and negative examples; flavor differences; when not to use regex | Extract fields from messy log lines → hidden examples parsed right |
| 12 | `shell-scripts` | K | 19 | N | Robust scripts and small CLIs: strict mode, quoting, exit codes, help, idempotence | Fragile deploy script → hidden checks with spaces in paths, missing args |
| **Test and verify** |
| 13 | `write-tests` | P | 22, 26 | A (superpowers testing references) | Tests that would catch real bugs; behavior over lines; find untested risk | Module without tests → the new tests kill ≥ N of M seeded mutants |
| 14 | `fix-flaky-tests` | T | 24 | A (superpowers condition-based-waiting, find-polluter) | Prove flakiness by repetition, classify (order, time, shared state, async), fix the cause, never skip | Order-dependent test → passes 30 runs in random order, not skipped |
| 15 | `verify-before-done` | P | 30, 77 | A (superpowers verification) | Evidence before any claim of done; a "not verified" list | Change that breaks a distant test → full suite green and the report says how it was checked |
| **Debug** |
| 16 | `systematic-debugging` | P | 31, 32, 34 | A (superpowers systematic-debugging) | Reproduce, isolate, find the root cause, fix there, prove it; stop after three failed fixes | Symptom in module A, cause in B → fix in B, hidden test passes |
| 17 | `bisect-regression` | T | 33 | N | Find the commit that broke something: a test script, `git bisect run`, skip unbuildable commits | 40-commit history, one regression → names the commit |
| 18 | `performance` | T | 35, 36, 67 | N | Measure first, profile, fix the hot spot, measure again, guard against regressions | Slow job whose hot spot isn't the obvious suspect → hidden timing passes, results unchanged |
| **Review and security** |
| 19 | `code-review` | P | 28 | A (Anthropic /code-review, superpowers reviewer) | Review a diff for real bugs; verify each finding before reporting; no style noise | Diff with 2 planted bugs and a bait → REVIEW.md names both, not the bait |
| 20 | `respond-to-review` | P | 29 | A (superpowers receiving-code-review) | Check each comment against the code before acting; push back on wrong ones with evidence | Review comments, one of them wrong → right ones applied, wrong one declined |
| 21 | `security-review` | P/T | 38, 39, 41 | A (Anthropic /security-review, ToB fp-check) | Find exploitable issues with an attack path each; secrets scan; few false positives | Service with SQL injection and path traversal plus a safe look-alike → both found, look-alike not |
| **Data, dependencies, build, release** |
| 22 | `database-migrations` | P/K | 43 | N | Safe, reversible migrations: expand/contract, backfill in batches, test up and down on real data | SQLite app needs a NOT NULL column → migration keeps data, has a down |
| 23 | `upgrade-dependencies` | P | 46, 40 | N | Upgrade one dependency at a time: read the changelog, fix breaking changes, audit known vulnerabilities | Local package v1→v2 with breaking changes in its changelog → tests pass on v2 |
| 24 | `fix-build-and-ci` | T | 47, 54 | A (OpenAI gh-fix-ci) | Read the first real error, reproduce locally, fix the cause; never weaken the check | Failing ci.sh (lint + tests) → passes, check not disabled |
| 25 | `release` | T | 48, 53 | N | Version bump in every place, changelog from user-facing changes, tag | Repo with commits since last tag → version consistent, changelog lists features and fixes, not chores |
| **Version control** |
| 26 | `commit-and-pr` | P | 50, 52 | N | Atomic commits with messages that say why; never commit secrets; PR description with how it was verified | Two unrelated changes plus a .env → two commits, .env not committed |
| 27 | `resolve-merge-conflicts` | T | 51 | N | Understand both sides' intent from history, combine them, test; never take one side wholesale | Conflicted merge where both sides matter → no markers, both behaviors tested |
| **Documentation** |
| 28 | `write-docs` | P | 60, 61, 62, 63 | N | READMEs, API docs and comments that are true: run every command shown; comment why, not what | Undocumented CLI → README whose commands all run |
| **Agent practice** |
| 29 | `handoff-notes` | P | 74, 72 | A (mattpocock handoff) | Notes another session can resume from: state, decisions, open threads, how to verify | Half-done task → HANDOFF.md a fresh run can finish from |
| 30 | `write-skills` | P | 76 | A (skill-creator + superpowers writing-skills) | Write a skill and its tests: trigger description, short body, cases with near misses, baseline comparison | Request for a project skill → valid SKILL.md and cases.json |

## 2. Routed packs (`packs/INDEX.md`)

Knowledge maintained by vendors and specialists; installed per project when its stack calls for them.

| Area | v0 items | Pack | License |
|---|---|---|---|
| React / Next.js / web UI rules | 18, 68 | vercel-labs/agent-skills (react-best-practices, web-design-guidelines) | MIT |
| Postgres schema, queries, locks | 10, 20, 44 | supabase/agent-skills postgres-best-practices | MIT |
| Terraform / Packer | 58 | hashicorp/agent-skills | MPL-2.0 |
| Python / C++ toolchains | 17 | trailofbits/skills modern-python, modern-cpp | CC-BY-SA-4.0 |
| SwiftUI | 17 | twostraws/SwiftUI-Agent-Skill swiftui-pro | MIT |
| Browser testing, UI from design | 23, 69 | anthropics/skills webapp-testing, frontend-design | Apache-2.0 |
| Fuzzing, property-based tests, SAST, supply chain | 25, 27, 40 | trailofbits/skills | CC-BY-SA-4.0 |
| GitHub Actions failures with `gh` | 54 | openai/skills gh-fix-ci | Apache-2.0 |
| Cloud platforms | 56 | Cloudflare, Vercel, Google, Microsoft skills | vendor |
| Git worktrees | 75 | obra/superpowers using-git-worktrees | MIT |

## 3. Not skills

| v0 items | Where it belongs instead |
|---|---|
| Destructive-action guardrails | kurtkode's permission rules, danger checks and hooks |
| 72 context management, 73 delegation | the harness and its system prompt (kurtkode's `delegation.md`) |
| 5 unfamiliar language | a rule inside `implement-change` (ground in the installed version's docs) |
| 9 API design, 42 auth, 45 ETL, 49 dev environments, 55 containers, 57 observability, 59 incidents, 66 tech debt, 70 CSS | low value as generic skills (models know the basics) or vendor-specific; candidates for a second tier if tests on real work show a need |
