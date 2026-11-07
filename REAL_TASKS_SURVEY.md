# Real-sized tasks: survey (2026-10-30)

What the real-sized task work has built and measured, whether the set is complete enough to use, and what it
concluded. The detail is in COST_AUDIT.md (P2, sections 10–11) and REAL_TASKS_PLAN.md; this is the summary.

## Why it exists

The bank (small synthetic fixtures) said the cheap tier was good enough: ling-3.0-flash passed 98%. COST_AUDIT's
finding F2 suspected that was a property of the fixtures. The real-sized tasks test that: tasks cut from real commits
of the user's own projects, graded by the project's own tests.

## What was built

36 tasks in seven sets under `eval-results/real-fixtures/`, run with `kurtkode-eval --bank real` (all) or
`--bank real:<set>`.

| set | tasks | repository | shape | gold |
|---|---|---|---|---|
| real1 (P2's) | rd01–rd06, rd08–rd10, rd12 | responsedigger (Python, 4,200 lines) | feature commit, its tests already in `tests/` | the suite passes, no existing test weakened |
| `rdh` | rdh01 fix, rdh02–03 edit | responsedigger | feature or fix; the commit's tests hidden | the suite with the hidden tests laid over |
| `kk` | kk01–02 fix, kk03–05 edit | kurtkode (Swift, 53k lines) | as `rdh` | serial `swift test` with a 19-test sandbox skip list, plus the hidden tests |
| `kkq` | kkq01 search, kkq02–03 explain | kurtkode | a question answered by reading the code | 8–12 facts matched in the report by regex |
| `rdw` | rdw01–03 write-tests | responsedigger | a fixed bug: "add tests that would have caught it" | the new tests pass on the fixed code and fail with the pre-fix code laid over |
| `pkg` | pkg01–08 | pypa/packaging (Python, 13k lines) | feature or fix; the commit's tests hidden | the suite with the hidden tests, run in the sandbox |
| `sqg` | sqg01–04 | sqlglot (Python, 84k lines) | as `pkg` | as `pkg` |

Tooling:

- **Building**: `spike/real-set-2/build_task.py` (fixture at the parent, hidden-test, buggy and reference overlays),
  `build_kk.sh` (rebuilds the gitignored kurtkode fixtures), `validate_task.py` (fail before, pass at gold, twice
  sandboxed and twice not). Every task was validated; every failure in the paid rows was checked by hand.
- **Harness** (`EvalKit/TaskBankReal.swift`): several sets, per-task kind (routed as the product routes a card),
  hidden-test, buggy and lookup checkers, a per-set prepare step (kurtkode's cold build).
- **Cascade mode** (`--cascade`, `EvalKit/Cascade.swift`): each task as a main run in a real CLI session, with the
  product's own escalation offer taken and the stronger model finishing through the product's hand-over.
- **Faults found on the way**, all fixed with tests and the stored runs re-graded: in grading, new test files counted
  as touching tests (P2), additive edits to test helpers, a new test file whose type clashes with a hidden one, and
  lookup patterns too narrow; in the harness, the review simulation's diff; in the product, the after-run suite check
  running from the model's last `cd` (2d4acf0).

Spend, all approved with `--max-cost`: P2 and P2b about $11.6, section 10's rows $24.11, the `rdw` pilot $0.05, the
Opus cascade $15.98, the public-repository round $9.85; about **$62** in all.

## What was measured

| row | models | tasks | result |
|---|---|---|---|
| P2/P2b | ling, deepseek-off, Haiku, Sonnet (subagent, 32k) | real1 | ling 10%, deepseek 72%, Haiku 83%, Sonnet 10/10 |
| Pilot + Main | ling, deepseek-off, Haiku, 3 trials (subagent, 32k) | rdh, kk, kkq | ling 33%, deepseek 42%, Haiku 76% |
| Frontier | Sonnet, 1 trial (32k) | rdh, kk, kkq | 10/11 |
| P3 at real size | Sonnet reviewing stored runs | real1, real2 failures and passes | see conclusion 6 |
| P5 | Haiku and deepseek as judges | bank1 | see conclusion 7 |
| Cascade | Haiku main runs → Sonnet (200k) | 21 tasks × 3 | 84% → 98%, $0.13 a run |
| `rdw` pilot | Haiku, 1 trial (200k) | rdw | 3/3, $0.05 |
| Opus cascade | Haiku main runs → Opus (200k) | 24 tasks × 3 | 83% → 93%, $0.22 a run |
| Public pilot + Main | ling, deepseek-off, Haiku, 3 trials (subagent, 200k) | pkg, sqg | ling 31%, deepseek 67%, Haiku 86% |
| Public cascade | Haiku main runs → Sonnet (200k) | pkg, sqg × 3 | 78% → 92%, $0.17 a run |

## Is it complete enough to use?

**Yes, for what it has been used for**: comparing the Claude tiers and the cheap tier on real edits, pricing the
cheap-first cascade, choosing the escalation target, and checking escalation and review changes before they ship. It
runs end to end with one command, every task is validated, and the grading faults found so far are fixed.

**Not yet, for three things it was meant to decide:**

1. **Generalization, in part.** `pkg` and `sqg` add two repositories from other authors, and Haiku holds up: 86%,
   against 83–84% on the user's own. Both are Python, so kurtkode is still the only other language, and it changes
   repository and language at once. A non-Python repository from another author would close this.
2. **The router.** It was shelved until about 100 labeled real failures exist. The subagent rows now give 119 (real1
   27, Main 49, Frontier 1, public Main 42), so the count is met, but the public rows ran at 200k and the others at
   32k, so they don't simply add. The three cascades' main-run failures are on repeated tasks in a different run mode.
   Reopening it is a decision still to make.
3. **Real-sized lookups and delegation.** Three lookups only (Haiku 7/9, deepseek 6/9, ling 5/9 in Main), and no task
   has been shown to need improvement 7's 30k-token delegation trigger. "Keep ling for lookups" rests on these three.

**Weaker spots to know about:**

- **Small samples.** Most cells are 3 trials; Haiku's 76% on the 11 has a 59–87% interval. Differences under about 15
  points between models are not established.
- **`rdw` is easy** (Haiku 3/3 at under 2¢), so it can't separate models. Its gold is lenient in two ways: tests need
  catch only one part of a multi-part fix, and a test that only imports a helper the fix added counts. Harder variants
  (no function names, fixes across modules) are not built.
- **Lookups get no escalation.** A lookup changes no files, so no grounded signal can fire on it; Haiku's lookup
  failures pass through the cascade unrescued (4 of its 5 final failures in the Opus cascade).
- **kurtkode and sqlglot fixtures aren't committed**; `build_kk.sh` and `build_sqg.sh` rebuild them from the
  repositories' history.
- **Missing shapes**: refactors, bug fixes with no test anywhere, and multi-turn sessions where the user steers.
- **Two open measurements**: the same-model retry on runaway reasoning (unbuilt), and 3b02e0b's escalation rules,
  which no live run has triggered yet (checked offline only: 2 fires on 794 stored runs, both real failures).

## Conclusions

1. **The bank's results don't transfer.** ling's 98% on the bank is 10% on real1 and 33% on the 11 newer tasks, and 0
   of 18 runs on the harder kurtkode edits (kk02–kk04), where deepseek-off also passed none. On sqlglot it passes 1 of
   12 and deepseek-off 4 of 12. The cheap tier is for small, bounded work.
2. **Haiku is the cheapest success on real edits**: $0.057–0.064 a success, against deepseek's $0.065–0.124 and
   Sonnet's $0.72–0.78 (11–14× Haiku). Sonnet passes more (91–100%), not by enough to pay for itself as a
   default. On the public sets ling's $0.027 a success beats Haiku's $0.036, but ling fails 69% of its runs.
3. **The cheap-first cascade works at real size.** Haiku main runs escalating to Sonnet reached 98% at $0.13 a run,
   about a fifth of Sonnet alone. Every offer was on a real failure and every escalation fixed it. The escalations are
   78% of the bill. On the public sets it went from 78% to 92% at $0.17 a run: `pkg` 24/24, sqlglot 9/12. There Sonnet
   rescued 5 of 7 failures, one offer fell on a passing run, and one silent failure drew no offer.
4. **The main escalation trigger is runaway reasoning, not tests.** 8 of 9 offers to Sonnet, 8 of 11 to Opus and 7 of 8
   on the public sets came from a reply cut off at the output limit, all 16,384 tokens spent thinking. A same-model
   retry (about $0.02 against $0.72) is the obvious next cost lever, though sqg01 cut Haiku off 6 times out of 6, so it
   won't help everywhere. Sonnet can be cut off too: it was, twice, on sqg01.
5. **The project's own tests (11b) are precise but reach little.** On these tasks they flagged 10 of 40 hidden-test
   failures, because the visible suite usually passes after a wrong change. They cost nothing and once caught a flaky
   test gold missed, so they stay, but they are not the cascade's main signal.
6. **Escalate to Sonnet, not Opus.** Opus rescued 7 of 8 at $1.57 each, Sonnet 9 of 9 at $0.72; Opus took more steps
   and hit the $2 run limit twice. The shipped pool now escalates to Sonnet (d75d401).
7. **At real size a review needs its strictest verdict.** Sonnet's review flagged 97% of real failures but also 60% of
   passes as "has problems"; "wrong" alone caught 74% with 1 false alarm in 47. Escalation after a review now needs
   "wrong" (section 11).
8. **A cheap judge's "fail" can be trusted; its "pass" can't.** Haiku and deepseek-off as judges raised no false alarm
   in about 180 passes each but missed about 4 failures in 10.
9. **Measure real work at the models' real context.** 32k depressed every model: rdh03 went from 0 of 10 runs at 32k
   to 3 of 3 at 200k, and Haiku from 76% (32k subagent) to 84% (200k main run). At 32k, main runs also gave up and wrote
   handoff notes, which led to two product fixes.
10. **Grading needs as much care as the models.** The paid rows turned up four faults in the checker and one in the
    review simulation, and each moved pass rates or review results. Check failures by hand before trusting a new rate.
