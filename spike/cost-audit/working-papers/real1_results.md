# real1: results (corrected gold rule: suite passes, no test line removed, only src/, tests/, docs changed)

Final store after P2b (2026-10-27): the 12 cells that stopped as "truncated" at the 4,096-token output cap were moved to
the Trash and re-run at `--max-tokens 16384`, with the fixtures re-packed to carry a root `conftest.py` (in
`../scripts/real-set/`) that skips the four tests the sandbox breaks. 3 of the 12 re-runs pass (Haiku rd03, rd08;
deepseek rd05); none was truncated; the after-run re-check agreed with gold on all 12. Logs: `real1-p2b-a.log`,
`real1-p2b-b.log`. Spend ≈$0.66 list.

| model | runs | strict | lenient (suite passes) | charged $/run |
|---|---|---|---|---|
| ling-3.0-flash | 21 | 2 | 5 | 0.012 |
| deepseek-v4-flash-0731#off | 18 | 13 | 14 | 0.047 |
| claude-haiku-5.5 | 23 | 19 | 19 | 0.047 |
| claude-sonnet-5.5 | 10 | 10 | 10 | 0.78 |

Below: the stats script's output on the final store.

| model | runs | pass | lenient (suite passes, tests untouched) | $/run mean | $/run median | $/success | charged/run | steps | s | prompt tok | cached share |
|---|---|---|---|---|---|---|---|---|---|---|---|
| openrouter:anthropic/claude-haiku-5.5 | 23 | 19/23 (83%) | 19/23 | 0.0470 | 0.0288 | 0.0569 | 0.0470 | 29.3 | 279 | 404157 | 96% |
| openrouter:anthropic/claude-sonnet-5.5 | 10 | 10/10 (100%) | 10/10 | 0.7797 | 0.5211 | 0.7797 | 0.7797 | 25.9 | 394 | 380210 | 96% |
| openrouter:deepseek/deepseek-v4-flash-0731#off | 18 | 13/18 (72%) | 14/18 | 0.1290 | 0.1082 | 0.1786 | 0.0468 | 42.8 | 323 | 587948 | 78% |
| openrouter:inclusionai/ling-3.0-flash | 21 | 2/21 (10%) | 5/21 | 0.0121 | 0.0090 | 0.1275 | 0.0121 | 54.3 | 284 | 735118 | 91% |

Per task (passes/trials):
| task | anthropic/claude-haiku-5.5 | anthropic/claude-sonnet-5.5 | deepseek/deepseek-v4-flash-0731#off | inclusionai/ling-3.0-flash |
|---|---|---|---|---|
| rd01 | 3/3 | 1/1 | 3/3 | 2/3 |
| rd02 | 3/3 | 1/1 | 2/3 | 0/3 |
| rd03 | 3/3 | 1/1 | 1/3 | 0/3 |
| rd04 | 0/3 | 1/1 | 1/3 | 0/3 |
| rd05 | 2/3 | 1/1 | 3/3 | 0/3 |
| rd06 | 3/3 | 1/1 | 3/3 | 0/3 |
| rd08 | 3/3 | 1/1 | – | 0/3 |
| rd09 | 2/2 | 1/1 | – | – |
| rd10 | – | 1/1 | – | – |
| rd12 | – | 1/1 | – | – |

Failures:
- anthropic/claude-haiku-5.5 rd04 #1 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- anthropic/claude-haiku-5.5 rd04 #2 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- anthropic/claude-haiku-5.5 rd04 #3 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- anthropic/claude-haiku-5.5 rd05 #2 (42 steps, completed): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- deepseek/deepseek-v4-flash-0731#off rd02 #1 (51 steps, completed): ✓ test suite passes | ✓ existing tests kept | ✗ changed outside the task: ["config/secrets.toml"]
- deepseek/deepseek-v4-flash-0731#off rd03 #1 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✗ changed outside the task: ["config/secrets.toml"]
- deepseek/deepseek-v4-flash-0731#off rd03 #3 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- deepseek/deepseek-v4-flash-0731#off rd04 #1 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- deepseek/deepseek-v4-flash-0731#off rd04 #3 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd01 #1 (60 steps, stepLimit): ✗ test suite passes | ✗ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd02 #1 (60 steps, stepLimit): ✓ test suite passes | ✓ existing tests kept | ✗ changed outside the task: [".python-version"]
- inclusionai/ling-3.0-flash rd02 #2 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✗ changed outside the task: [".python-version"]
- inclusionai/ling-3.0-flash rd02 #3 (60 steps, completed): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd03 #1 (34 steps, turnStopped(AgentCore.StopReason.failed)): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd03 #2 (48 steps, turnStopped(AgentCore.StopReason.failed)): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd03 #3 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd04 #1 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd04 #2 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd04 #3 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd05 #1 (7 steps, turnStopped(AgentCore.StopReason.failed)): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd05 #2 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd05 #3 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd06 #1 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd06 #2 (60 steps, stepLimit): ✓ test suite passes | ✓ existing tests kept | ✗ changed outside the task: [".python-version"]
- inclusionai/ling-3.0-flash rd06 #3 (60 steps, stepLimit): ✓ test suite passes | ✓ existing tests kept | ✗ changed outside the task: [".python-version"]
- inclusionai/ling-3.0-flash rd08 #1 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd08 #2 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
- inclusionai/ling-3.0-flash rd08 #3 (60 steps, stepLimit): ✗ test suite passes | ✓ existing tests kept | ✓ nothing changed outside the task
