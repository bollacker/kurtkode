## Escalation triggers on stored runs (cf2, cf6, cf3a, cf3b, bank1, p1-after)

### bank1|*

612 runs, 42 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 612 | 4 | 3 | 75% | 7% |
| the re-run check failed | 612 | 3 | 3 | 100% | 7% |
| a hard failure | 612 | 10 | 7 | 70% | 17% |
| stopped early | 612 | 6 | 4 | 67% | 10% |
| its last check failed | 612 | 3 | 2 | 67% | 5% |
| unfinished todos | 612 | 0 | 0 | – | 0% |
| changed files it didn't mention | 612 | 4 | 1 | 25% | 2% |
| repeated a call | 612 | 83 | 6 | 7% | 14% |
| any grounded signal | 612 | 13 | 7 | 54% | 17% |
| judge: grader gemini-3.8-flash ≤ 1 | 204 | 9 | 5 | 56% | 36% |
| judge: grader gemini-4-argon ≤ 1 | 204 | 7 | 5 | 71% | 36% |
| judge: grader gemma-4-26b-a4b-qat ≤ 1 | 155 | 7 | 4 | 57% | 29% |
| judge: grader qwen3.5-9b ≤ 1 | 196 | 33 | 8 | 24% | 57% |
| judge: parent gemini-3.8-flash ≤ 1 | 203 | 8 | 8 | 100% | 57% |
| judge: parent gemini-4-argon ≤ 1 | 204 | 10 | 10 | 100% | 71% |
| judge: parent gemma-4-26b-a4b-qat ≤ 1 | 125 | 3 | 2 | 67% | 20% |
| judge: parent qwen3.5-9b ≤ 1 | 192 | 10 | 4 | 40% | 31% |
| review: google-gemini:gemini-3.8-flash found a problem | 32 | 6 | 6 | 100% | 75% |
| review: lmstudio:qwen/qwen3-coder-30b found a problem | 32 | 5 | 5 | 100% | 63% |
| review: openrouter:anthropic/claude-haiku-5.5 found a problem | 32 | 10 | 8 | 80% | 100% |
| review: openrouter:deepseek/deepseek-v4-flash-0731#off found a problem | 32 | 6 | 6 | 100% | 75% |
| grounded or grader gemini-3.8-flash ≤ 1 | 204 | 9 | 5 | 56% | 36% |
| grounded or grader gemini-4-argon ≤ 1 | 204 | 8 | 5 | 63% | 36% |
| grounded or grader gemma-4-26b-a4b-qat ≤ 1 | 155 | 7 | 4 | 57% | 29% |
| grounded or grader qwen3.5-9b ≤ 1 | 196 | 33 | 8 | 24% | 57% |
| grounded or parent gemini-3.8-flash ≤ 1 | 203 | 9 | 8 | 89% | 57% |
| grounded or parent gemini-4-argon ≤ 1 | 204 | 11 | 10 | 91% | 71% |
| grounded or parent gemma-4-26b-a4b-qat ≤ 1 | 125 | 3 | 2 | 67% | 20% |
| grounded or parent qwen3.5-9b ≤ 1 | 192 | 10 | 4 | 40% | 31% |
| grounded or review google-gemini:gemini-3.8-flash | 32 | 6 | 6 | 100% | 75% |
| grounded or review lmstudio:qwen/qwen3-coder-30b | 32 | 5 | 5 | 100% | 63% |
| grounded or review openrouter:anthropic/claude-haiku-5.5 | 32 | 10 | 8 | 80% | 100% |
| grounded or review openrouter:deepseek/deepseek-v4-flash-0731#off | 32 | 6 | 6 | 100% | 75% |

### bank1|bang:qwen/qwen3.5-9b

102 runs, 12 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 102 | 1 | 0 | 0% | 0% |
| the re-run check failed | 102 | 0 | 0 | – | 0% |
| a hard failure | 102 | 3 | 1 | 33% | 8% |
| stopped early | 102 | 0 | 0 | – | 0% |
| its last check failed | 102 | 0 | 0 | – | 0% |
| unfinished todos | 102 | 0 | 0 | – | 0% |
| changed files it didn't mention | 102 | 0 | 0 | – | 0% |
| repeated a call | 102 | 16 | 0 | 0% | 0% |
| any grounded signal | 102 | 4 | 1 | 25% | 8% |
| judge: grader gemini-3.8-flash ≤ 1 | 34 | 3 | 2 | 67% | 50% |
| judge: grader gemini-4-argon ≤ 1 | 34 | 4 | 3 | 75% | 75% |
| judge: grader gemma-4-26b-a4b-qat ≤ 1 | 26 | 2 | 1 | 50% | 25% |
| judge: grader qwen3.5-9b ≤ 1 | 33 | 8 | 3 | 38% | 75% |
| judge: parent gemini-3.8-flash ≤ 1 | 34 | 2 | 2 | 100% | 50% |
| judge: parent gemini-4-argon ≤ 1 | 34 | 3 | 3 | 100% | 75% |
| judge: parent gemma-4-26b-a4b-qat ≤ 1 | 23 | 1 | 0 | 0% | 0% |
| judge: parent qwen3.5-9b ≤ 1 | 32 | 2 | 0 | 0% | 0% |
| review: google-gemini:gemini-3.8-flash found a problem | 3 | 0 | 0 | – | – |
| review: lmstudio:qwen/qwen3-coder-30b found a problem | 3 | 0 | 0 | – | – |
| review: openrouter:anthropic/claude-haiku-5.5 found a problem | 3 | 0 | 0 | – | – |
| review: openrouter:deepseek/deepseek-v4-flash-0731#off found a problem | 3 | 0 | 0 | – | – |
| grounded or grader gemini-3.8-flash ≤ 1 | 34 | 3 | 2 | 67% | 50% |
| grounded or grader gemini-4-argon ≤ 1 | 34 | 5 | 3 | 60% | 75% |
| grounded or grader gemma-4-26b-a4b-qat ≤ 1 | 26 | 2 | 1 | 50% | 25% |
| grounded or grader qwen3.5-9b ≤ 1 | 33 | 8 | 3 | 38% | 75% |
| grounded or parent gemini-3.8-flash ≤ 1 | 34 | 3 | 2 | 67% | 50% |
| grounded or parent gemini-4-argon ≤ 1 | 34 | 4 | 3 | 75% | 75% |
| grounded or parent gemma-4-26b-a4b-qat ≤ 1 | 23 | 1 | 0 | 0% | 0% |
| grounded or parent qwen3.5-9b ≤ 1 | 32 | 2 | 0 | 0% | 0% |
| grounded or review google-gemini:gemini-3.8-flash | 3 | 0 | 0 | – | – |
| grounded or review lmstudio:qwen/qwen3-coder-30b | 3 | 0 | 0 | – | – |
| grounded or review openrouter:anthropic/claude-haiku-5.5 | 3 | 0 | 0 | – | – |
| grounded or review openrouter:deepseek/deepseek-v4-flash-0731#off | 3 | 0 | 0 | – | – |

### bank1|google-gemini:gemini-3.6-flash

102 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 102 | 0 | 0 | – | – |
| the re-run check failed | 102 | 0 | 0 | – | – |
| a hard failure | 102 | 0 | 0 | – | – |
| stopped early | 102 | 0 | 0 | – | – |
| its last check failed | 102 | 0 | 0 | – | – |
| unfinished todos | 102 | 0 | 0 | – | – |
| changed files it didn't mention | 102 | 0 | 0 | – | – |
| repeated a call | 102 | 18 | 0 | 0% | – |
| any grounded signal | 102 | 0 | 0 | – | – |
| judge: grader gemini-3.8-flash ≤ 1 | 34 | 0 | 0 | – | – |
| judge: grader gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| judge: grader gemma-4-26b-a4b-qat ≤ 1 | 26 | 0 | 0 | – | – |
| judge: grader qwen3.5-9b ≤ 1 | 34 | 3 | 0 | 0% | – |
| judge: parent gemini-3.8-flash ≤ 1 | 34 | 0 | 0 | – | – |
| judge: parent gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| judge: parent gemma-4-26b-a4b-qat ≤ 1 | 20 | 0 | 0 | – | – |
| judge: parent qwen3.5-9b ≤ 1 | 34 | 0 | 0 | – | – |
| review: google-gemini:gemini-3.8-flash found a problem | 6 | 0 | 0 | – | – |
| review: lmstudio:qwen/qwen3-coder-30b found a problem | 6 | 0 | 0 | – | – |
| review: openrouter:anthropic/claude-haiku-5.5 found a problem | 6 | 1 | 0 | 0% | – |
| review: openrouter:deepseek/deepseek-v4-flash-0731#off found a problem | 6 | 0 | 0 | – | – |
| grounded or grader gemini-3.8-flash ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or grader gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or grader gemma-4-26b-a4b-qat ≤ 1 | 26 | 0 | 0 | – | – |
| grounded or grader qwen3.5-9b ≤ 1 | 34 | 3 | 0 | 0% | – |
| grounded or parent gemini-3.8-flash ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or parent gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or parent gemma-4-26b-a4b-qat ≤ 1 | 20 | 0 | 0 | – | – |
| grounded or parent qwen3.5-9b ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or review google-gemini:gemini-3.8-flash | 6 | 0 | 0 | – | – |
| grounded or review lmstudio:qwen/qwen3-coder-30b | 6 | 0 | 0 | – | – |
| grounded or review openrouter:anthropic/claude-haiku-5.5 | 6 | 1 | 0 | 0% | – |
| grounded or review openrouter:deepseek/deepseek-v4-flash-0731#off | 6 | 0 | 0 | – | – |

### bank1|google-gemini:gemini-3.8-flash

102 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 102 | 0 | 0 | – | – |
| the re-run check failed | 102 | 0 | 0 | – | – |
| a hard failure | 102 | 0 | 0 | – | – |
| stopped early | 102 | 0 | 0 | – | – |
| its last check failed | 102 | 0 | 0 | – | – |
| unfinished todos | 102 | 0 | 0 | – | – |
| changed files it didn't mention | 102 | 0 | 0 | – | – |
| repeated a call | 102 | 19 | 0 | 0% | – |
| any grounded signal | 102 | 0 | 0 | – | – |
| judge: grader gemini-3.8-flash ≤ 1 | 34 | 1 | 0 | 0% | – |
| judge: grader gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| judge: grader gemma-4-26b-a4b-qat ≤ 1 | 24 | 0 | 0 | – | – |
| judge: grader qwen3.5-9b ≤ 1 | 33 | 2 | 0 | 0% | – |
| judge: parent gemini-3.8-flash ≤ 1 | 34 | 0 | 0 | – | – |
| judge: parent gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| judge: parent gemma-4-26b-a4b-qat ≤ 1 | 18 | 0 | 0 | – | – |
| judge: parent qwen3.5-9b ≤ 1 | 33 | 0 | 0 | – | – |
| review: google-gemini:gemini-3.8-flash found a problem | 2 | 0 | 0 | – | – |
| review: lmstudio:qwen/qwen3-coder-30b found a problem | 2 | 0 | 0 | – | – |
| review: openrouter:anthropic/claude-haiku-5.5 found a problem | 2 | 0 | 0 | – | – |
| review: openrouter:deepseek/deepseek-v4-flash-0731#off found a problem | 2 | 0 | 0 | – | – |
| grounded or grader gemini-3.8-flash ≤ 1 | 34 | 1 | 0 | 0% | – |
| grounded or grader gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or grader gemma-4-26b-a4b-qat ≤ 1 | 24 | 0 | 0 | – | – |
| grounded or grader qwen3.5-9b ≤ 1 | 33 | 2 | 0 | 0% | – |
| grounded or parent gemini-3.8-flash ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or parent gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or parent gemma-4-26b-a4b-qat ≤ 1 | 18 | 0 | 0 | – | – |
| grounded or parent qwen3.5-9b ≤ 1 | 33 | 0 | 0 | – | – |
| grounded or review google-gemini:gemini-3.8-flash | 2 | 0 | 0 | – | – |
| grounded or review lmstudio:qwen/qwen3-coder-30b | 2 | 0 | 0 | – | – |
| grounded or review openrouter:anthropic/claude-haiku-5.5 | 2 | 0 | 0 | – | – |
| grounded or review openrouter:deepseek/deepseek-v4-flash-0731#off | 2 | 0 | 0 | – | – |

### bank1|google-gemini:gemini-4-argon

102 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 102 | 0 | 0 | – | – |
| the re-run check failed | 102 | 0 | 0 | – | – |
| a hard failure | 102 | 0 | 0 | – | – |
| stopped early | 102 | 0 | 0 | – | – |
| its last check failed | 102 | 1 | 0 | 0% | – |
| unfinished todos | 102 | 0 | 0 | – | – |
| changed files it didn't mention | 102 | 0 | 0 | – | – |
| repeated a call | 102 | 3 | 0 | 0% | – |
| any grounded signal | 102 | 1 | 0 | 0% | – |
| judge: grader gemini-3.8-flash ≤ 1 | 34 | 1 | 0 | 0% | – |
| judge: grader gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| judge: grader gemma-4-26b-a4b-qat ≤ 1 | 23 | 0 | 0 | – | – |
| judge: grader qwen3.5-9b ≤ 1 | 34 | 3 | 0 | 0% | – |
| judge: parent gemini-3.8-flash ≤ 1 | 34 | 0 | 0 | – | – |
| judge: parent gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| judge: parent gemma-4-26b-a4b-qat ≤ 1 | 21 | 0 | 0 | – | – |
| judge: parent qwen3.5-9b ≤ 1 | 33 | 1 | 0 | 0% | – |
| review: google-gemini:gemini-3.8-flash found a problem | 7 | 0 | 0 | – | – |
| review: lmstudio:qwen/qwen3-coder-30b found a problem | 7 | 0 | 0 | – | – |
| review: openrouter:anthropic/claude-haiku-5.5 found a problem | 7 | 0 | 0 | – | – |
| review: openrouter:deepseek/deepseek-v4-flash-0731#off found a problem | 7 | 0 | 0 | – | – |
| grounded or grader gemini-3.8-flash ≤ 1 | 34 | 1 | 0 | 0% | – |
| grounded or grader gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or grader gemma-4-26b-a4b-qat ≤ 1 | 23 | 0 | 0 | – | – |
| grounded or grader qwen3.5-9b ≤ 1 | 34 | 3 | 0 | 0% | – |
| grounded or parent gemini-3.8-flash ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or parent gemini-4-argon ≤ 1 | 34 | 0 | 0 | – | – |
| grounded or parent gemma-4-26b-a4b-qat ≤ 1 | 21 | 0 | 0 | – | – |
| grounded or parent qwen3.5-9b ≤ 1 | 33 | 1 | 0 | 0% | – |
| grounded or review google-gemini:gemini-3.8-flash | 7 | 0 | 0 | – | – |
| grounded or review lmstudio:qwen/qwen3-coder-30b | 7 | 0 | 0 | – | – |
| grounded or review openrouter:anthropic/claude-haiku-5.5 | 7 | 0 | 0 | – | – |
| grounded or review openrouter:deepseek/deepseek-v4-flash-0731#off | 7 | 0 | 0 | – | – |

### bank1|lmstudio:gemma-4-e4b-it

102 runs, 19 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 102 | 3 | 3 | 100% | 16% |
| the re-run check failed | 102 | 3 | 3 | 100% | 16% |
| a hard failure | 102 | 3 | 3 | 100% | 16% |
| stopped early | 102 | 1 | 1 | 100% | 5% |
| its last check failed | 102 | 2 | 2 | 100% | 11% |
| unfinished todos | 102 | 0 | 0 | – | 0% |
| changed files it didn't mention | 102 | 1 | 1 | 100% | 5% |
| repeated a call | 102 | 13 | 6 | 46% | 32% |
| any grounded signal | 102 | 3 | 3 | 100% | 16% |
| judge: grader gemini-3.8-flash ≤ 1 | 34 | 2 | 1 | 50% | 17% |
| judge: grader gemini-4-argon ≤ 1 | 34 | 1 | 1 | 100% | 17% |
| judge: grader gemma-4-26b-a4b-qat ≤ 1 | 31 | 3 | 1 | 33% | 17% |
| judge: grader qwen3.5-9b ≤ 1 | 31 | 9 | 3 | 33% | 50% |
| judge: parent gemini-3.8-flash ≤ 1 | 34 | 3 | 3 | 100% | 50% |
| judge: parent gemini-4-argon ≤ 1 | 34 | 4 | 4 | 100% | 67% |
| judge: parent gemma-4-26b-a4b-qat ≤ 1 | 23 | 2 | 2 | 100% | 33% |
| judge: parent qwen3.5-9b ≤ 1 | 29 | 4 | 2 | 50% | 40% |
| review: google-gemini:gemini-3.8-flash found a problem | 11 | 6 | 6 | 100% | 100% |
| review: lmstudio:qwen/qwen3-coder-30b found a problem | 11 | 5 | 5 | 100% | 83% |
| review: openrouter:anthropic/claude-haiku-5.5 found a problem | 11 | 6 | 6 | 100% | 100% |
| review: openrouter:deepseek/deepseek-v4-flash-0731#off found a problem | 11 | 6 | 6 | 100% | 100% |
| grounded or grader gemini-3.8-flash ≤ 1 | 34 | 2 | 1 | 50% | 17% |
| grounded or grader gemini-4-argon ≤ 1 | 34 | 1 | 1 | 100% | 17% |
| grounded or grader gemma-4-26b-a4b-qat ≤ 1 | 31 | 3 | 1 | 33% | 17% |
| grounded or grader qwen3.5-9b ≤ 1 | 31 | 9 | 3 | 33% | 50% |
| grounded or parent gemini-3.8-flash ≤ 1 | 34 | 3 | 3 | 100% | 50% |
| grounded or parent gemini-4-argon ≤ 1 | 34 | 4 | 4 | 100% | 67% |
| grounded or parent gemma-4-26b-a4b-qat ≤ 1 | 23 | 2 | 2 | 100% | 33% |
| grounded or parent qwen3.5-9b ≤ 1 | 29 | 4 | 2 | 50% | 40% |
| grounded or review google-gemini:gemini-3.8-flash | 11 | 6 | 6 | 100% | 100% |
| grounded or review lmstudio:qwen/qwen3-coder-30b | 11 | 5 | 5 | 100% | 83% |
| grounded or review openrouter:anthropic/claude-haiku-5.5 | 11 | 6 | 6 | 100% | 100% |
| grounded or review openrouter:deepseek/deepseek-v4-flash-0731#off | 11 | 6 | 6 | 100% | 100% |

### bank1|lmstudio:google/gemma-4-26b-a4b-qat

102 runs, 11 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 102 | 0 | 0 | – | 0% |
| the re-run check failed | 102 | 0 | 0 | – | 0% |
| a hard failure | 102 | 4 | 3 | 75% | 27% |
| stopped early | 102 | 5 | 3 | 60% | 27% |
| its last check failed | 102 | 0 | 0 | – | 0% |
| unfinished todos | 102 | 0 | 0 | – | 0% |
| changed files it didn't mention | 102 | 3 | 0 | 0% | 0% |
| repeated a call | 102 | 14 | 0 | 0% | 0% |
| any grounded signal | 102 | 5 | 3 | 60% | 27% |
| judge: grader gemini-3.8-flash ≤ 1 | 34 | 2 | 2 | 100% | 50% |
| judge: grader gemini-4-argon ≤ 1 | 34 | 2 | 1 | 50% | 25% |
| judge: grader gemma-4-26b-a4b-qat ≤ 1 | 25 | 2 | 2 | 100% | 50% |
| judge: grader qwen3.5-9b ≤ 1 | 31 | 8 | 2 | 25% | 50% |
| judge: parent gemini-3.8-flash ≤ 1 | 33 | 3 | 3 | 100% | 75% |
| judge: parent gemini-4-argon ≤ 1 | 34 | 3 | 3 | 100% | 75% |
| judge: parent gemma-4-26b-a4b-qat ≤ 1 | 20 | 0 | 0 | – | 0% |
| judge: parent qwen3.5-9b ≤ 1 | 31 | 3 | 2 | 67% | 50% |
| review: google-gemini:gemini-3.8-flash found a problem | 3 | 0 | 0 | – | 0% |
| review: lmstudio:qwen/qwen3-coder-30b found a problem | 3 | 0 | 0 | – | 0% |
| review: openrouter:anthropic/claude-haiku-5.5 found a problem | 3 | 3 | 2 | 67% | 100% |
| review: openrouter:deepseek/deepseek-v4-flash-0731#off found a problem | 3 | 0 | 0 | – | 0% |
| grounded or grader gemini-3.8-flash ≤ 1 | 34 | 2 | 2 | 100% | 50% |
| grounded or grader gemini-4-argon ≤ 1 | 34 | 2 | 1 | 50% | 25% |
| grounded or grader gemma-4-26b-a4b-qat ≤ 1 | 25 | 2 | 2 | 100% | 50% |
| grounded or grader qwen3.5-9b ≤ 1 | 31 | 8 | 2 | 25% | 50% |
| grounded or parent gemini-3.8-flash ≤ 1 | 33 | 3 | 3 | 100% | 75% |
| grounded or parent gemini-4-argon ≤ 1 | 34 | 3 | 3 | 100% | 75% |
| grounded or parent gemma-4-26b-a4b-qat ≤ 1 | 20 | 0 | 0 | – | 0% |
| grounded or parent qwen3.5-9b ≤ 1 | 31 | 3 | 2 | 67% | 50% |
| grounded or review google-gemini:gemini-3.8-flash | 3 | 0 | 0 | – | 0% |
| grounded or review lmstudio:qwen/qwen3-coder-30b | 3 | 0 | 0 | – | 0% |
| grounded or review openrouter:anthropic/claude-haiku-5.5 | 3 | 3 | 2 | 67% | 100% |
| grounded or review openrouter:deepseek/deepseek-v4-flash-0731#off | 3 | 0 | 0 | – | 0% |

### cf2|*

9958 runs, 628 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 9958 | 84 | 22 | 26% | 4% |
| the re-run check failed | 9958 | 20 | 20 | 100% | 3% |
| a hard failure | 9958 | 263 | 100 | 38% | 16% |
| stopped early | 9958 | 52 | 50 | 96% | 8% |
| its last check failed | 9958 | 6 | 6 | 100% | 1% |
| unfinished todos | 9958 | 5 | 3 | 60% | 0% |
| changed files it didn't mention | 9958 | 38 | 9 | 24% | 1% |
| repeated a call | 9958 | 701 | 58 | 8% | 9% |
| any grounded signal | 9958 | 330 | 103 | 31% | 16% |

### cf2|openrouter:aion-labs/aion-2.0

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:aion-labs/aion-3.0-mini

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 1 | 50% | 100% |
| stopped early | 28 | 1 | 1 | 100% | 100% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 3 | 1 | 33% | 100% |

### cf2|openrouter:anthropic/claude-haiku-5.5

280 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 0 | 0 | – | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 7 | 0 | 0% | 0% |
| stopped early | 280 | 0 | 0 | – | 0% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 0 | 0 | – | 0% |
| repeated a call | 280 | 2 | 0 | 0% | 0% |
| any grounded signal | 280 | 7 | 0 | 0% | 0% |

### cf2|openrouter:anthropic/claude-haiku-5.5#off

280 runs, 8 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 0 | 0 | – | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 2 | 0 | 0% | 0% |
| stopped early | 280 | 0 | 0 | – | 0% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 0 | 0 | – | 0% |
| repeated a call | 280 | 3 | 0 | 0% | 0% |
| any grounded signal | 280 | 2 | 0 | 0% | 0% |

### cf2|openrouter:bytedance-seed/seed-1.6

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 1 | 100% | 33% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 1 | 100% | 33% |

### cf2|openrouter:bytedance-seed/seed-1.6#off

16 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 16 | 0 | 0 | – | 0% |
| the re-run check failed | 16 | 0 | 0 | – | 0% |
| a hard failure | 16 | 0 | 0 | – | 0% |
| stopped early | 16 | 0 | 0 | – | 0% |
| its last check failed | 16 | 0 | 0 | – | 0% |
| unfinished todos | 16 | 0 | 0 | – | 0% |
| changed files it didn't mention | 16 | 0 | 0 | – | 0% |
| repeated a call | 16 | 0 | 0 | – | 0% |
| any grounded signal | 16 | 0 | 0 | – | 0% |

### cf2|openrouter:bytedance-seed/seed-2-1-turbo

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:bytedance-seed/seed-2-1-turbo#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:bytedance-seed/seed-2.0-lite

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:bytedance-seed/seed-2.0-lite#off

19 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 19 | 0 | 0 | – | 0% |
| the re-run check failed | 19 | 0 | 0 | – | 0% |
| a hard failure | 19 | 1 | 1 | 100% | 25% |
| stopped early | 19 | 0 | 0 | – | 0% |
| its last check failed | 19 | 0 | 0 | – | 0% |
| unfinished todos | 19 | 0 | 0 | – | 0% |
| changed files it didn't mention | 19 | 0 | 0 | – | 0% |
| repeated a call | 19 | 0 | 0 | – | 0% |
| any grounded signal | 19 | 1 | 1 | 100% | 25% |

### cf2|openrouter:bytedance-seed/seed-2.0-mini

84 runs, 8 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 2 | 1 | 50% | 13% |
| the re-run check failed | 84 | 1 | 1 | 100% | 13% |
| a hard failure | 84 | 2 | 0 | 0% | 0% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 4 | 1 | 25% | 13% |
| any grounded signal | 84 | 4 | 1 | 25% | 13% |

### cf2|openrouter:bytedance-seed/seed-2.0-mini#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:cohere/command-a-plus

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 50% |
| stopped early | 28 | 1 | 1 | 100% | 50% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 5 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 1 | 50% | 50% |

### cf2|openrouter:deepseek/deepseek-chat

17 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 17 | 0 | 0 | – | 0% |
| the re-run check failed | 17 | 0 | 0 | – | 0% |
| a hard failure | 17 | 0 | 0 | – | 0% |
| stopped early | 17 | 0 | 0 | – | 0% |
| its last check failed | 17 | 0 | 0 | – | 0% |
| unfinished todos | 17 | 0 | 0 | – | 0% |
| changed files it didn't mention | 17 | 0 | 0 | – | 0% |
| repeated a call | 17 | 1 | 1 | 100% | 17% |
| any grounded signal | 17 | 0 | 0 | – | 0% |

### cf2|openrouter:deepseek/deepseek-chat-v3-0324

17 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 17 | 0 | 0 | – | 0% |
| the re-run check failed | 17 | 0 | 0 | – | 0% |
| a hard failure | 17 | 0 | 0 | – | 0% |
| stopped early | 17 | 0 | 0 | – | 0% |
| its last check failed | 17 | 0 | 0 | – | 0% |
| unfinished todos | 17 | 0 | 0 | – | 0% |
| changed files it didn't mention | 17 | 0 | 0 | – | 0% |
| repeated a call | 17 | 0 | 0 | – | 0% |
| any grounded signal | 17 | 0 | 0 | – | 0% |

### cf2|openrouter:deepseek/deepseek-chat-v3.1

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 100% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 5 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 1 | 100% | 100% |

### cf2|openrouter:deepseek/deepseek-chat-v3.1#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 1 | 25% | 100% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:deepseek/deepseek-v3.1-terminus

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:deepseek/deepseek-v3.1-terminus#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 5 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:deepseek/deepseek-v3.2

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 6 | 2 | 33% | 100% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:deepseek/deepseek-v3.2#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 1 | 50% | 100% |
| stopped early | 28 | 1 | 1 | 100% | 100% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 5 | 1 | 20% | 100% |
| any grounded signal | 28 | 2 | 1 | 50% | 100% |

### cf2|openrouter:deepseek/deepseek-v3.2-exp

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 1 | 0 | 0% | – |
| repeated a call | 28 | 9 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:deepseek/deepseek-v3.2-exp#off

26 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 26 | 0 | 0 | – | 0% |
| the re-run check failed | 26 | 0 | 0 | – | 0% |
| a hard failure | 26 | 2 | 2 | 100% | 67% |
| stopped early | 26 | 2 | 2 | 100% | 67% |
| its last check failed | 26 | 0 | 0 | – | 0% |
| unfinished todos | 26 | 0 | 0 | – | 0% |
| changed files it didn't mention | 26 | 0 | 0 | – | 0% |
| repeated a call | 26 | 9 | 2 | 22% | 67% |
| any grounded signal | 26 | 2 | 2 | 100% | 67% |

### cf2|openrouter:deepseek/deepseek-v4-flash

280 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 4 | 0 | 0% | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 12 | 1 | 8% | 50% |
| stopped early | 280 | 1 | 1 | 100% | 50% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 1 | 0 | 0% | 0% |
| repeated a call | 280 | 11 | 0 | 0% | 0% |
| any grounded signal | 280 | 16 | 1 | 6% | 50% |

### cf2|openrouter:deepseek/deepseek-v4-flash#off

280 runs, 9 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 4 | 0 | 0% | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 7 | 0 | 0% | 0% |
| stopped early | 280 | 0 | 0 | – | 0% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 1 | 0 | 0% | 0% |
| repeated a call | 280 | 13 | 1 | 8% | 11% |
| any grounded signal | 280 | 11 | 0 | 0% | 0% |

### cf2|openrouter:deepseek/deepseek-v4-flash-0731

280 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 0 | 0 | – | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 5 | 0 | 0% | 0% |
| stopped early | 280 | 0 | 0 | – | 0% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 0 | 0 | – | 0% |
| repeated a call | 280 | 11 | 0 | 0% | 0% |
| any grounded signal | 280 | 5 | 0 | 0% | 0% |

### cf2|openrouter:deepseek/deepseek-v4-flash-0731#off

280 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 0 | 0 | – | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 7 | 0 | 0% | 0% |
| stopped early | 280 | 0 | 0 | – | 0% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 0 | 0 | – | 0% |
| repeated a call | 280 | 13 | 0 | 0% | 0% |
| any grounded signal | 280 | 7 | 0 | 0% | 0% |

### cf2|openrouter:deepseek/deepseek-v4-flash-vision-exp

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:deepseek/deepseek-v4-flash-vision-exp#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:deepseek/deepseek-v4-pro

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:deepseek/deepseek-v4-pro#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:deepseek/deepseek-v4-pro-0813

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:deepseek/deepseek-v4-pro-0813#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:deepseek/deepseek-v4.1-flash

280 runs, 15 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 0 | 0 | – | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 9 | 6 | 67% | 40% |
| stopped early | 280 | 6 | 6 | 100% | 40% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 0 | 0 | – | 0% |
| repeated a call | 280 | 18 | 2 | 11% | 13% |
| any grounded signal | 280 | 9 | 6 | 67% | 40% |

### cf2|openrouter:deepseek/deepseek-v4.1-flash#off

84 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 0 | 0 | – | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 1 | 0 | 0% | 0% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 5 | 0 | 0% | 0% |
| any grounded signal | 84 | 1 | 0 | 0% | 0% |

### cf2|openrouter:deepseek/deepseek-v4.1-flash-1017

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:deepseek/deepseek-v4.1-flash-1017#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 1 | 50% | 33% |
| stopped early | 28 | 1 | 1 | 100% | 33% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 1 | 25% | 33% |
| any grounded signal | 28 | 2 | 1 | 50% | 33% |

### cf2|openrouter:elorian/glimpse

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:elorian/glimpse#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:google/gemini-2.5-flash

17 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 17 | 0 | 0 | – | 0% |
| the re-run check failed | 17 | 0 | 0 | – | 0% |
| a hard failure | 17 | 0 | 0 | – | 0% |
| stopped early | 17 | 0 | 0 | – | 0% |
| its last check failed | 17 | 0 | 0 | – | 0% |
| unfinished todos | 17 | 0 | 0 | – | 0% |
| changed files it didn't mention | 17 | 0 | 0 | – | 0% |
| repeated a call | 17 | 1 | 1 | 100% | 17% |
| any grounded signal | 17 | 0 | 0 | – | 0% |

### cf2|openrouter:google/gemini-2.5-flash#off

12 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 12 | 0 | 0 | – | 0% |
| the re-run check failed | 12 | 0 | 0 | – | 0% |
| a hard failure | 12 | 0 | 0 | – | 0% |
| stopped early | 12 | 0 | 0 | – | 0% |
| its last check failed | 12 | 0 | 0 | – | 0% |
| unfinished todos | 12 | 0 | 0 | – | 0% |
| changed files it didn't mention | 12 | 1 | 0 | 0% | 0% |
| repeated a call | 12 | 0 | 0 | – | 0% |
| any grounded signal | 12 | 0 | 0 | – | 0% |

### cf2|openrouter:google/gemini-3-flash-preview

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:google/gemini-3-flash-preview#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 1 | 25% | 50% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:google/gemini-3.1-flash-lite

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 9 | 1 | 11% | 50% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:google/gemini-3.1-flash-lite#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 10 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:google/gemini-3.1-flash-lite-preview

17 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 17 | 0 | 0 | – | 0% |
| the re-run check failed | 17 | 0 | 0 | – | 0% |
| a hard failure | 17 | 1 | 1 | 100% | 20% |
| stopped early | 17 | 0 | 0 | – | 0% |
| its last check failed | 17 | 0 | 0 | – | 0% |
| unfinished todos | 17 | 0 | 0 | – | 0% |
| changed files it didn't mention | 17 | 0 | 0 | – | 0% |
| repeated a call | 17 | 5 | 1 | 20% | 20% |
| any grounded signal | 17 | 1 | 1 | 100% | 20% |

### cf2|openrouter:google/gemini-3.1-flash-lite-preview#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 8 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:google/gemini-3.7-flash

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:google/gemma-4-26b-a4b-it

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 1 | 100% | 33% |
| the re-run check failed | 28 | 1 | 1 | 100% | 33% |
| a hard failure | 28 | 2 | 2 | 100% | 67% |
| stopped early | 28 | 2 | 2 | 100% | 67% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 1 | 1 | 100% | 33% |
| changed files it didn't mention | 28 | 1 | 0 | 0% | 0% |
| repeated a call | 28 | 7 | 2 | 29% | 67% |
| any grounded signal | 28 | 2 | 2 | 100% | 67% |

### cf2|openrouter:google/gemma-4-26b-a4b-it#off

28 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 1 | 100% | 20% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 2 | 100% | 40% |
| stopped early | 28 | 2 | 2 | 100% | 40% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 1 | 0 | 0% | 0% |
| changed files it didn't mention | 28 | 2 | 1 | 50% | 20% |
| repeated a call | 28 | 4 | 1 | 25% | 20% |
| any grounded signal | 28 | 3 | 2 | 67% | 40% |

### cf2|openrouter:google/gemma-4-31b-it

28 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 2 | 0 | 0% | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:google/gemma-4-31b-it#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 3 | 0 | 0% | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:ibm-granite/granite-4.2-8b

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 1 | 50% | 33% |
| the re-run check failed | 28 | 1 | 1 | 100% | 33% |
| a hard failure | 28 | 2 | 2 | 100% | 67% |
| stopped early | 28 | 2 | 2 | 100% | 67% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 3 | 2 | 67% | 67% |

### cf2|openrouter:ibm-granite/granite-4.2-8b#off

28 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 1 | 100% | 20% |
| the re-run check failed | 28 | 1 | 1 | 100% | 20% |
| a hard failure | 28 | 1 | 1 | 100% | 20% |
| stopped early | 28 | 1 | 1 | 100% | 20% |
| its last check failed | 28 | 1 | 1 | 100% | 20% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 1 | 1 | 100% | 20% |
| repeated a call | 28 | 5 | 2 | 40% | 40% |
| any grounded signal | 28 | 1 | 1 | 100% | 20% |

### cf2|openrouter:inception/mercury-2

28 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:inception/mercury-2.5

280 runs, 13 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 0 | 0 | – | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 9 | 1 | 11% | 8% |
| stopped early | 280 | 0 | 0 | – | 0% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 0 | 0 | – | 0% |
| repeated a call | 280 | 17 | 0 | 0% | 0% |
| any grounded signal | 280 | 9 | 1 | 11% | 8% |

### cf2|openrouter:inception/mercury-2.5#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:inception/mercury-3

280 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 0 | 0 | – | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 5 | 0 | 0% | 0% |
| stopped early | 280 | 0 | 0 | – | 0% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 0 | 0 | – | 0% |
| repeated a call | 280 | 9 | 0 | 0% | 0% |
| any grounded signal | 280 | 5 | 0 | 0% | 0% |

### cf2|openrouter:inception/mercury-3#off

84 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 0 | 0 | – | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 2 | 0 | 0% | 0% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 2 | 0 | 0% | 0% |
| any grounded signal | 84 | 2 | 0 | 0% | 0% |

### cf2|openrouter:inclusionai/ling-3.0-flash

280 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 0 | 0 | – | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 4 | 0 | 0% | 0% |
| stopped early | 280 | 0 | 0 | – | 0% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 0 | 0 | – | 0% |
| repeated a call | 280 | 20 | 1 | 5% | 20% |
| any grounded signal | 280 | 4 | 0 | 0% | 0% |

### cf2|openrouter:inclusionai/ling-3.0-flash#off

28 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 1 | 33% | 25% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:inclusionai/ling-3.1-flash

84 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 1 | 1 | 100% | 20% |
| the re-run check failed | 84 | 1 | 1 | 100% | 20% |
| a hard failure | 84 | 5 | 2 | 40% | 40% |
| stopped early | 84 | 1 | 1 | 100% | 20% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 2 | 0 | 0% | 0% |
| any grounded signal | 84 | 5 | 2 | 40% | 40% |

### cf2|openrouter:inclusionai/ling-3.1-flash#off

84 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 0 | 0 | – | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 1 | 0 | 0% | 0% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 5 | 0 | 0% | 0% |
| any grounded signal | 84 | 1 | 0 | 0% | 0% |

### cf2|openrouter:liquid/lfm-2.5-24b-a2b

84 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 3 | 0 | 0% | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 3 | 0 | 0% | 0% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 13 | 0 | 0% | 0% |
| any grounded signal | 84 | 6 | 0 | 0% | 0% |

### cf2|openrouter:meituan/longcat-2.0

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:meituan/longcat-2.0#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:meta/muse-glimmer-30b

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 3 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:meta/muse-spark-1.1

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:meta/muse-spark-1.2

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:minimax/minimax-m1#off

9 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 9 | 0 | 0 | – | 0% |
| the re-run check failed | 9 | 0 | 0 | – | 0% |
| a hard failure | 9 | 2 | 2 | 100% | 50% |
| stopped early | 9 | 0 | 0 | – | 0% |
| its last check failed | 9 | 0 | 0 | – | 0% |
| unfinished todos | 9 | 0 | 0 | – | 0% |
| changed files it didn't mention | 9 | 1 | 0 | 0% | 0% |
| repeated a call | 9 | 0 | 0 | – | 0% |
| any grounded signal | 9 | 2 | 2 | 100% | 50% |

### cf2|openrouter:minimax/minimax-m2

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 1 | 50% | 50% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 2 | 1 | 50% | 50% |

### cf2|openrouter:minimax/minimax-m2.1

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:minimax/minimax-m2.5

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:minimax/minimax-m2.7

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:minimax/minimax-m3

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 2 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:minimax/minimax-m3#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:minimax/minimax-m3.1-flash

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 50% |
| stopped early | 28 | 1 | 1 | 100% | 50% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 1 | 100% | 50% |

### cf2|openrouter:mistralai/devstral-2512

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:mistralai/ministral-14b-2512

17 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 17 | 1 | 0 | 0% | 0% |
| the re-run check failed | 17 | 0 | 0 | – | 0% |
| a hard failure | 17 | 1 | 1 | 100% | 17% |
| stopped early | 17 | 0 | 0 | – | 0% |
| its last check failed | 17 | 0 | 0 | – | 0% |
| unfinished todos | 17 | 0 | 0 | – | 0% |
| changed files it didn't mention | 17 | 1 | 0 | 0% | 0% |
| repeated a call | 17 | 1 | 0 | 0% | 0% |
| any grounded signal | 17 | 2 | 1 | 50% | 17% |

### cf2|openrouter:mistralai/ministral-8b-2512

18 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 18 | 0 | 0 | – | 0% |
| the re-run check failed | 18 | 0 | 0 | – | 0% |
| a hard failure | 18 | 0 | 0 | – | 0% |
| stopped early | 18 | 0 | 0 | – | 0% |
| its last check failed | 18 | 0 | 0 | – | 0% |
| unfinished todos | 18 | 0 | 0 | – | 0% |
| changed files it didn't mention | 18 | 0 | 0 | – | 0% |
| repeated a call | 18 | 0 | 0 | – | 0% |
| any grounded signal | 18 | 0 | 0 | – | 0% |

### cf2|openrouter:mistralai/mistral-large-4-0

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:mistralai/mistral-large-4-0#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:mistralai/mistral-medium-3

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:mistralai/mistral-medium-3.1

18 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 18 | 0 | 0 | – | 0% |
| the re-run check failed | 18 | 0 | 0 | – | 0% |
| a hard failure | 18 | 0 | 0 | – | 0% |
| stopped early | 18 | 0 | 0 | – | 0% |
| its last check failed | 18 | 0 | 0 | – | 0% |
| unfinished todos | 18 | 0 | 0 | – | 0% |
| changed files it didn't mention | 18 | 0 | 0 | – | 0% |
| repeated a call | 18 | 1 | 0 | 0% | 0% |
| any grounded signal | 18 | 0 | 0 | – | 0% |

### cf2|openrouter:mistralai/mistral-saba

17 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 17 | 0 | 0 | – | 0% |
| the re-run check failed | 17 | 0 | 0 | – | 0% |
| a hard failure | 17 | 0 | 0 | – | 0% |
| stopped early | 17 | 0 | 0 | – | 0% |
| its last check failed | 17 | 0 | 0 | – | 0% |
| unfinished todos | 17 | 0 | 0 | – | 0% |
| changed files it didn't mention | 17 | 0 | 0 | – | 0% |
| repeated a call | 17 | 1 | 0 | 0% | 0% |
| any grounded signal | 17 | 0 | 0 | – | 0% |

### cf2|openrouter:mistralai/mistral-small-2603

18 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 18 | 1 | 0 | 0% | 0% |
| the re-run check failed | 18 | 0 | 0 | – | 0% |
| a hard failure | 18 | 0 | 0 | – | 0% |
| stopped early | 18 | 0 | 0 | – | 0% |
| its last check failed | 18 | 0 | 0 | – | 0% |
| unfinished todos | 18 | 0 | 0 | – | 0% |
| changed files it didn't mention | 18 | 0 | 0 | – | 0% |
| repeated a call | 18 | 1 | 0 | 0% | 0% |
| any grounded signal | 18 | 1 | 0 | 0% | 0% |

### cf2|openrouter:mistralai/mistral-small-2603#off

14 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 14 | 0 | 0 | – | 0% |
| the re-run check failed | 14 | 0 | 0 | – | 0% |
| a hard failure | 14 | 0 | 0 | – | 0% |
| stopped early | 14 | 0 | 0 | – | 0% |
| its last check failed | 14 | 0 | 0 | – | 0% |
| unfinished todos | 14 | 0 | 0 | – | 0% |
| changed files it didn't mention | 14 | 0 | 0 | – | 0% |
| repeated a call | 14 | 1 | 0 | 0% | 0% |
| any grounded signal | 14 | 0 | 0 | – | 0% |

### cf2|openrouter:mistralai/mixtral-8x22b-instruct

19 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 19 | 0 | 0 | – | 0% |
| the re-run check failed | 19 | 0 | 0 | – | 0% |
| a hard failure | 19 | 0 | 0 | – | 0% |
| stopped early | 19 | 1 | 0 | 0% | 0% |
| its last check failed | 19 | 0 | 0 | – | 0% |
| unfinished todos | 19 | 0 | 0 | – | 0% |
| changed files it didn't mention | 19 | 1 | 0 | 0% | 0% |
| repeated a call | 19 | 0 | 0 | – | 0% |
| any grounded signal | 19 | 1 | 0 | 0% | 0% |

### cf2|openrouter:moonshotai/kimi-k2

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 33% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 1 | 100% | 33% |

### cf2|openrouter:moonshotai/kimi-k2-0905

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:moonshotai/kimi-k2-thinking

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 2 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:moonshotai/kimi-k2.5

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:moonshotai/kimi-k2.5#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 2 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:moonshotai/kimi-k2.6

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:moonshotai/kimi-k2.6#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 50% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 1 | 100% | 50% |

### cf2|openrouter:moonshotai/kimi-k2.7-code

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:moonshotai/kimi-k3

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 2 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:moonshotai/kimi-k3#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:nex-agi/nex-n2.5-pro

25 runs, 11 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 25 | 2 | 2 | 100% | 18% |
| the re-run check failed | 25 | 2 | 2 | 100% | 18% |
| a hard failure | 25 | 9 | 9 | 100% | 82% |
| stopped early | 25 | 0 | 0 | – | 0% |
| its last check failed | 25 | 0 | 0 | – | 0% |
| unfinished todos | 25 | 2 | 2 | 100% | 18% |
| changed files it didn't mention | 25 | 0 | 0 | – | 0% |
| repeated a call | 25 | 0 | 0 | – | 0% |
| any grounded signal | 25 | 9 | 9 | 100% | 82% |

### cf2|openrouter:nex-agi/nex-n2.5-pro#off

28 runs, 7 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 3 | 3 | 100% | 43% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 3 | 3 | 100% | 43% |

### cf2|openrouter:nvidia/nemotron-3-nano-30b-a3b

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 33% |
| stopped early | 28 | 1 | 1 | 100% | 33% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 1 | 0 | 0% | 0% |
| repeated a call | 28 | 5 | 0 | 0% | 0% |
| any grounded signal | 28 | 3 | 1 | 33% | 33% |

### cf2|openrouter:nvidia/nemotron-3-nano-30b-a3b#off

28 runs, 11 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 1 | 50% | 9% |
| the re-run check failed | 28 | 1 | 1 | 100% | 9% |
| a hard failure | 28 | 3 | 3 | 100% | 27% |
| stopped early | 28 | 2 | 2 | 100% | 18% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 1 | 0 | 0% | 0% |
| changed files it didn't mention | 28 | 1 | 1 | 100% | 9% |
| repeated a call | 28 | 7 | 4 | 57% | 36% |
| any grounded signal | 28 | 5 | 4 | 80% | 36% |

### cf2|openrouter:nvidia/nemotron-3-super-120b-a12b

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 1 | 50% | 33% |
| stopped early | 28 | 1 | 1 | 100% | 33% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 3 | 1 | 33% | 33% |

### cf2|openrouter:nvidia/nemotron-3-super-120b-a12b#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:nvidia/nemotron-3-ultra-550b-a55b

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 1 | 0 | 0% | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:nvidia/nemotron-3-ultra-550b-a55b#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 50% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 1 | 0 | 0% | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 1 | 1 | 100% | 50% |

### cf2|openrouter:nvidia/nemotron-3.5-lightning

28 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 2 | 100% | 50% |
| stopped early | 28 | 1 | 1 | 100% | 25% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 1 | 0 | 0% | 0% |
| repeated a call | 28 | 9 | 3 | 33% | 75% |
| any grounded signal | 28 | 4 | 2 | 50% | 50% |

### cf2|openrouter:nvidia/nemotron-3.5-lightning#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 1 | 0 | 0% | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 10 | 1 | 10% | 50% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:nvidia/nemotron-3.5-super-vl

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:nvidia/nemotron-3.5-super-vl#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:openai/gpt-4.1-mini

14 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 14 | 1 | 1 | 100% | 20% |
| the re-run check failed | 14 | 1 | 1 | 100% | 20% |
| a hard failure | 14 | 1 | 1 | 100% | 20% |
| stopped early | 14 | 1 | 1 | 100% | 20% |
| its last check failed | 14 | 0 | 0 | – | 0% |
| unfinished todos | 14 | 0 | 0 | – | 0% |
| changed files it didn't mention | 14 | 1 | 1 | 100% | 20% |
| repeated a call | 14 | 1 | 1 | 100% | 20% |
| any grounded signal | 14 | 1 | 1 | 100% | 20% |

### cf2|openrouter:openai/gpt-5-mini

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 1 | 50% | 50% |
| the re-run check failed | 28 | 1 | 1 | 100% | 50% |
| a hard failure | 28 | 1 | 1 | 100% | 50% |
| stopped early | 28 | 1 | 1 | 100% | 50% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 2 | 1 | 50% | 50% |
| repeated a call | 28 | 5 | 1 | 20% | 50% |
| any grounded signal | 28 | 2 | 1 | 50% | 50% |

### cf2|openrouter:openai/gpt-5-nano

28 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 1 | 50% | 20% |
| the re-run check failed | 28 | 1 | 1 | 100% | 20% |
| a hard failure | 28 | 2 | 2 | 100% | 40% |
| stopped early | 28 | 2 | 2 | 100% | 40% |
| its last check failed | 28 | 1 | 1 | 100% | 20% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 1 | 1 | 100% | 20% |
| repeated a call | 28 | 5 | 1 | 20% | 20% |
| any grounded signal | 28 | 3 | 2 | 67% | 40% |

### cf2|openrouter:openai/gpt-5.1-codex-mini

13 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 13 | 0 | 0 | – | 0% |
| the re-run check failed | 13 | 0 | 0 | – | 0% |
| a hard failure | 13 | 2 | 2 | 100% | 50% |
| stopped early | 13 | 0 | 0 | – | 0% |
| its last check failed | 13 | 0 | 0 | – | 0% |
| unfinished todos | 13 | 0 | 0 | – | 0% |
| changed files it didn't mention | 13 | 0 | 0 | – | 0% |
| repeated a call | 13 | 2 | 1 | 50% | 25% |
| any grounded signal | 13 | 2 | 2 | 100% | 50% |

### cf2|openrouter:openai/gpt-5.4-mini

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-5.4-mini#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-5.4-nano

19 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 19 | 0 | 0 | – | 0% |
| the re-run check failed | 19 | 0 | 0 | – | 0% |
| a hard failure | 19 | 0 | 0 | – | 0% |
| stopped early | 19 | 0 | 0 | – | 0% |
| its last check failed | 19 | 0 | 0 | – | 0% |
| unfinished todos | 19 | 0 | 0 | – | 0% |
| changed files it didn't mention | 19 | 0 | 0 | – | 0% |
| repeated a call | 19 | 2 | 0 | 0% | 0% |
| any grounded signal | 19 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-5.4-nano#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 6 | 2 | 33% | 67% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-5.6-luna

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-5.6-luna#off

27 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 27 | 0 | 0 | – | 0% |
| the re-run check failed | 27 | 0 | 0 | – | 0% |
| a hard failure | 27 | 0 | 0 | – | 0% |
| stopped early | 27 | 0 | 0 | – | 0% |
| its last check failed | 27 | 0 | 0 | – | 0% |
| unfinished todos | 27 | 0 | 0 | – | 0% |
| changed files it didn't mention | 27 | 0 | 0 | – | 0% |
| repeated a call | 27 | 1 | 0 | 0% | 0% |
| any grounded signal | 27 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-5.6-luna-pro

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-5.6-luna-pro#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-6-luna

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-6-luna#off

28 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-6-luna-pro

84 runs, 8 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 0 | 0 | – | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 0 | 0 | – | 0% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 0 | 0 | – | 0% |
| any grounded signal | 84 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-6-luna-pro#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:openai/gpt-oss-120b

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:openai/gpt-oss-20b

28 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 1 | 50% | 20% |
| the re-run check failed | 28 | 1 | 1 | 100% | 20% |
| a hard failure | 28 | 2 | 1 | 50% | 20% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 0 | 0% | 0% |
| any grounded signal | 28 | 3 | 1 | 33% | 20% |

### cf2|openrouter:openai/gpt-oss-safeguard-20b

28 runs, 9 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 2 | 100% | 22% |
| the re-run check failed | 28 | 2 | 2 | 100% | 22% |
| a hard failure | 28 | 9 | 8 | 89% | 89% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 1 | 25% | 11% |
| any grounded signal | 28 | 9 | 8 | 89% | 89% |

### cf2|openrouter:poolside/laguna-s-2.1

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:poolside/laguna-s-2.1#off

280 runs, 13 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 0 | 0 | – | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 8 | 0 | 0% | 0% |
| stopped early | 280 | 0 | 0 | – | 0% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 0 | 0 | – | 0% |
| repeated a call | 280 | 23 | 0 | 0% | 0% |
| any grounded signal | 280 | 8 | 0 | 0% | 0% |

### cf2|openrouter:poolside/laguna-xs-2.1

84 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 1 | 0 | 0% | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 0 | 0 | – | 0% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 7 | 1 | 14% | 17% |
| any grounded signal | 84 | 1 | 0 | 0% | 0% |

### cf2|openrouter:poolside/laguna-xs-2.1#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:prism-ml/ternary-bonsai-2-27b

84 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 2 | 1 | 50% | 17% |
| the re-run check failed | 84 | 1 | 1 | 100% | 17% |
| a hard failure | 84 | 5 | 4 | 80% | 67% |
| stopped early | 84 | 2 | 2 | 100% | 33% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 4 | 0 | 0% | 0% |
| any grounded signal | 84 | 6 | 4 | 67% | 67% |

### cf2|openrouter:qwen/qwen-2.5-72b-instruct

17 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 17 | 1 | 1 | 100% | 20% |
| the re-run check failed | 17 | 1 | 1 | 100% | 20% |
| a hard failure | 17 | 1 | 1 | 100% | 20% |
| stopped early | 17 | 0 | 0 | – | 0% |
| its last check failed | 17 | 1 | 1 | 100% | 20% |
| unfinished todos | 17 | 0 | 0 | – | 0% |
| changed files it didn't mention | 17 | 0 | 0 | – | 0% |
| repeated a call | 17 | 1 | 1 | 100% | 20% |
| any grounded signal | 17 | 1 | 1 | 100% | 20% |

### cf2|openrouter:qwen/qwen-plus

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3-235b-a22b-2507

28 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 1 | 0 | 0% | 0% |
| repeated a call | 28 | 3 | 2 | 67% | 40% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3-235b-a22b-thinking-2507

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 2 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 3 | 0 | 0% | – |
| any grounded signal | 28 | 2 | 0 | 0% | – |

### cf2|openrouter:qwen/qwen3-30b-a3b-instruct-2507

28 runs, 8 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 1 | 100% | 13% |
| the re-run check failed | 28 | 1 | 1 | 100% | 13% |
| a hard failure | 28 | 1 | 1 | 100% | 13% |
| stopped early | 28 | 1 | 1 | 100% | 13% |
| its last check failed | 28 | 1 | 1 | 100% | 13% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 2 | 1 | 50% | 13% |
| repeated a call | 28 | 1 | 1 | 100% | 13% |
| any grounded signal | 28 | 1 | 1 | 100% | 13% |

### cf2|openrouter:qwen/qwen3-coder

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3-coder-30b-a3b-instruct

28 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 6 | 1 | 17% | 17% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3-coder-flash

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 2 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 10 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3-coder-next

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 1 | 0 | 0% | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3-next-80b-a3b-instruct

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3-vl-235b-a22b-instruct

19 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 19 | 0 | 0 | – | 0% |
| the re-run check failed | 19 | 0 | 0 | – | 0% |
| a hard failure | 19 | 0 | 0 | – | 0% |
| stopped early | 19 | 0 | 0 | – | 0% |
| its last check failed | 19 | 0 | 0 | – | 0% |
| unfinished todos | 19 | 0 | 0 | – | 0% |
| changed files it didn't mention | 19 | 1 | 0 | 0% | 0% |
| repeated a call | 19 | 0 | 0 | – | 0% |
| any grounded signal | 19 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3-vl-30b-a3b-instruct

12 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 12 | 1 | 1 | 100% | 25% |
| the re-run check failed | 12 | 1 | 1 | 100% | 25% |
| a hard failure | 12 | 1 | 1 | 100% | 25% |
| stopped early | 12 | 1 | 1 | 100% | 25% |
| its last check failed | 12 | 0 | 0 | – | 0% |
| unfinished todos | 12 | 0 | 0 | – | 0% |
| changed files it didn't mention | 12 | 1 | 1 | 100% | 25% |
| repeated a call | 12 | 2 | 1 | 50% | 25% |
| any grounded signal | 12 | 1 | 1 | 100% | 25% |

### cf2|openrouter:qwen/qwen3.5-122b-a10b

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.5-122b-a10b#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:qwen/qwen3.5-27b

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.5-27b#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3.5-35b-a3b

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 1 | 0 | 0% | – |
| repeated a call | 28 | 3 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:qwen/qwen3.5-35b-a3b#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3.5-397b-a17b

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 3 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:qwen/qwen3.5-397b-a17b#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.5-9b

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 6 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.5-9b#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 50% |
| stopped early | 28 | 1 | 1 | 100% | 50% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 1 | 33% | 50% |
| any grounded signal | 28 | 1 | 1 | 100% | 50% |

### cf2|openrouter:qwen/qwen3.5-flash-02-23

84 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 0 | 0 | – | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 5 | 0 | 0% | 0% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 1 | 0 | 0% | 0% |
| repeated a call | 84 | 11 | 0 | 0% | 0% |
| any grounded signal | 84 | 5 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3.5-flash-02-23#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.5-plus-02-15

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:qwen/qwen3.5-plus-02-15#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:qwen/qwen3.5-plus-20260420

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:qwen/qwen3.5-plus-20260420#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.6-27b

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 2 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 2 | 0 | 0% | – |

### cf2|openrouter:qwen/qwen3.6-27b#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 1 | 50% | 33% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 1 | 50% | 33% |

### cf2|openrouter:qwen/qwen3.6-35b-a3b

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.6-35b-a3b#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.6-flash

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.6-flash#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.6-plus

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3.6-plus#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.7-flash

84 runs, 7 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 2 | 0 | 0% | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 3 | 1 | 33% | 14% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 1 | 0 | 0% | 0% |
| repeated a call | 84 | 7 | 0 | 0% | 0% |
| any grounded signal | 84 | 5 | 1 | 20% | 14% |

### cf2|openrouter:qwen/qwen3.7-flash#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.7-max#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 50% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 1 | 100% | 50% |

### cf2|openrouter:qwen/qwen3.7-plus

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:qwen/qwen3.7-plus#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.8-27b

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3.8-27b#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 1 | 100% | 50% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:qwen/qwen3.8-flash

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.8-flash#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 3 | 2 | 67% | 100% |
| stopped early | 28 | 2 | 2 | 100% | 100% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 1 | 100% | 50% |
| any grounded signal | 28 | 3 | 2 | 67% | 100% |

### cf2|openrouter:qwen/qwen3.8-omni-flash

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:qwen/qwen3.8-omni-flash#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:reflection/beam-1.0-501b-a23b

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 5 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:stepfun/step-3.5-flash

280 runs, 11 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 280 | 5 | 0 | 0% | 0% |
| the re-run check failed | 280 | 0 | 0 | – | 0% |
| a hard failure | 280 | 9 | 4 | 44% | 36% |
| stopped early | 280 | 4 | 4 | 100% | 36% |
| its last check failed | 280 | 0 | 0 | – | 0% |
| unfinished todos | 280 | 0 | 0 | – | 0% |
| changed files it didn't mention | 280 | 2 | 0 | 0% | 0% |
| repeated a call | 280 | 26 | 0 | 0% | 0% |
| any grounded signal | 280 | 13 | 4 | 31% | 36% |

### cf2|openrouter:stepfun/step-3.7-flash

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:stepfun/step-5-preview

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 50% |
| stopped early | 28 | 1 | 1 | 100% | 50% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 1 | 50% | 50% |

### cf2|openrouter:tencent/hy3

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:tencent/hy3#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:tencent/hy3-preview

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 2 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 2 | 0 | 0% | – |

### cf2|openrouter:tencent/hy3-preview#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:tencent/hy4-preview

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 3 | 2 | 67% | 67% |
| stopped early | 28 | 2 | 2 | 100% | 67% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 3 | 2 | 67% | 67% |

### cf2|openrouter:tencent/hy4-preview#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:thinkingmachines/inkling

28 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 1 | 33% | 25% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:thinkingmachines/inkling#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:thinkingmachines/inkling-small

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:thinkingmachines/inkling-small#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:unbiased/pareto-26.10

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 2 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:upstage/solar-mini4

28 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 1 | 50% | 25% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 1 | 50% | 25% |

### cf2|openrouter:upstage/solar-mini4#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 5 | 1 | 20% | 33% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:upstage/solar-pro-3

11 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 11 | 2 | 2 | 100% | 40% |
| the re-run check failed | 11 | 2 | 2 | 100% | 40% |
| a hard failure | 11 | 3 | 3 | 100% | 60% |
| stopped early | 11 | 1 | 1 | 100% | 20% |
| its last check failed | 11 | 2 | 2 | 100% | 40% |
| unfinished todos | 11 | 0 | 0 | – | 0% |
| changed files it didn't mention | 11 | 1 | 1 | 100% | 20% |
| repeated a call | 11 | 8 | 4 | 50% | 80% |
| any grounded signal | 11 | 3 | 3 | 100% | 60% |

### cf2|openrouter:upstage/solar-pro4

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:upstage/solar-pro4#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:x-ai/grok-4.20

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 50% |
| stopped early | 28 | 1 | 1 | 100% | 50% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 8 | 1 | 13% | 50% |
| any grounded signal | 28 | 1 | 1 | 100% | 50% |

### cf2|openrouter:xiaomi/mimo-v2.5-pro

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:xiaomi/mimo-v2.6-flash

84 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 0 | 0 | – | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 4 | 3 | 75% | 100% |
| stopped early | 84 | 3 | 3 | 100% | 100% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 6 | 1 | 17% | 33% |
| any grounded signal | 84 | 4 | 3 | 75% | 100% |

### cf2|openrouter:xiaomi/mimo-v2.6-flash#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:xiaomi/mimo-v2.6-pro

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:xiaomi/mimo-v2.6-pro#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:z-ai/glm-4.5

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 2 | 0 | 0% | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:z-ai/glm-4.5#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:z-ai/glm-4.5-air

19 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 19 | 1 | 0 | 0% | 0% |
| the re-run check failed | 19 | 0 | 0 | – | 0% |
| a hard failure | 19 | 0 | 0 | – | 0% |
| stopped early | 19 | 0 | 0 | – | 0% |
| its last check failed | 19 | 0 | 0 | – | 0% |
| unfinished todos | 19 | 0 | 0 | – | 0% |
| changed files it didn't mention | 19 | 0 | 0 | – | 0% |
| repeated a call | 19 | 3 | 0 | 0% | 0% |
| any grounded signal | 19 | 1 | 0 | 0% | 0% |

### cf2|openrouter:z-ai/glm-4.5-air#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:z-ai/glm-4.5v

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:z-ai/glm-4.5v#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 33% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 1 | 1 | 100% | 33% |

### cf2|openrouter:z-ai/glm-4.6

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:z-ai/glm-4.6#off

19 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 19 | 1 | 0 | 0% | 0% |
| the re-run check failed | 19 | 0 | 0 | – | 0% |
| a hard failure | 19 | 0 | 0 | – | 0% |
| stopped early | 19 | 0 | 0 | – | 0% |
| its last check failed | 19 | 0 | 0 | – | 0% |
| unfinished todos | 19 | 0 | 0 | – | 0% |
| changed files it didn't mention | 19 | 0 | 0 | – | 0% |
| repeated a call | 19 | 1 | 1 | 100% | 25% |
| any grounded signal | 19 | 1 | 0 | 0% | 0% |

### cf2|openrouter:z-ai/glm-4.7

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:z-ai/glm-4.7#off

28 runs, 3 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:z-ai/glm-4.7-flash

84 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 84 | 2 | 0 | 0% | 0% |
| the re-run check failed | 84 | 0 | 0 | – | 0% |
| a hard failure | 84 | 1 | 1 | 100% | 17% |
| stopped early | 84 | 0 | 0 | – | 0% |
| its last check failed | 84 | 0 | 0 | – | 0% |
| unfinished todos | 84 | 0 | 0 | – | 0% |
| changed files it didn't mention | 84 | 0 | 0 | – | 0% |
| repeated a call | 84 | 11 | 0 | 0% | 0% |
| any grounded signal | 84 | 3 | 1 | 33% | 17% |

### cf2|openrouter:z-ai/glm-4.7-flash#off

28 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 1 | 0 | 0% | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 25% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 0 | 0% | 0% |
| any grounded signal | 28 | 2 | 1 | 50% | 25% |

### cf2|openrouter:z-ai/glm-5

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 2 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 2 | 0 | 0% | – |
| any grounded signal | 28 | 2 | 0 | 0% | – |

### cf2|openrouter:z-ai/glm-5#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 1 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:z-ai/glm-5-turbo

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:z-ai/glm-5-turbo#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:z-ai/glm-5.1

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:z-ai/glm-5.1#off

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 1 | 100% | 100% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 4 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 1 | 100% | 100% |

### cf2|openrouter:z-ai/glm-5.2

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 2 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 2 | 0 | 0% | 0% |

### cf2|openrouter:z-ai/glm-5.2#off

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 1 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 1 | 0 | 0% | – |
| any grounded signal | 28 | 1 | 0 | 0% | – |

### cf2|openrouter:z-ai/glm-5.3

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 0 | 0 | – | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 0 | 0 | – | – |
| any grounded signal | 28 | 0 | 0 | – | – |

### cf2|openrouter:z-ai/glm-5.3-flash

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 0 | 0 | – | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 3 | 1 | 33% | 100% |
| any grounded signal | 28 | 0 | 0 | – | 0% |

### cf2|openrouter:z-ai/glm-5.3-flashx

28 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | – |
| the re-run check failed | 28 | 0 | 0 | – | – |
| a hard failure | 28 | 2 | 0 | 0% | – |
| stopped early | 28 | 0 | 0 | – | – |
| its last check failed | 28 | 0 | 0 | – | – |
| unfinished todos | 28 | 0 | 0 | – | – |
| changed files it didn't mention | 28 | 0 | 0 | – | – |
| repeated a call | 28 | 2 | 0 | 0% | – |
| any grounded signal | 28 | 2 | 0 | 0% | – |

### cf2|openrouter:z-ai/glm-5v-turbo

28 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 0 | 0 | – | 0% |
| repeated a call | 28 | 2 | 0 | 0% | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf2|openrouter:z-ai/glm-5v-turbo#off

28 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 28 | 0 | 0 | – | 0% |
| the re-run check failed | 28 | 0 | 0 | – | 0% |
| a hard failure | 28 | 1 | 0 | 0% | 0% |
| stopped early | 28 | 0 | 0 | – | 0% |
| its last check failed | 28 | 0 | 0 | – | 0% |
| unfinished todos | 28 | 0 | 0 | – | 0% |
| changed files it didn't mention | 28 | 1 | 0 | 0% | 0% |
| repeated a call | 28 | 0 | 0 | – | 0% |
| any grounded signal | 28 | 1 | 0 | 0% | 0% |

### cf3a|*

2226 runs, 70 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 2226 | 72 | 11 | 15% | 16% |
| the re-run check failed | 2226 | 6 | 6 | 100% | 9% |
| a hard failure | 2226 | 112 | 13 | 12% | 19% |
| stopped early | 2226 | 15 | 9 | 60% | 13% |
| its last check failed | 2226 | 2 | 0 | 0% | 0% |
| unfinished todos | 2226 | 8 | 3 | 38% | 4% |
| changed files it didn't mention | 2226 | 20 | 5 | 25% | 7% |
| repeated a call | 2226 | 225 | 8 | 4% | 11% |
| any grounded signal | 2226 | 168 | 16 | 10% | 23% |
| judge: grader claude-haiku-5.5 ≤ 1 | 140 | 29 | 7 | 24% | 58% |
| judge: grader deepseek-v4-flash-0731#off ≤ 1 | 58 | 9 | 2 | 22% | 25% |
| judge: grader qwen3-coder-30b ≤ 1 | 89 | 14 | 3 | 21% | 27% |
| judge: parent claude-haiku-5.5 ≤ 1 | 140 | 9 | 3 | 33% | 25% |
| judge: parent deepseek-v4-flash-0731#off ≤ 1 | 137 | 6 | 4 | 67% | 44% |
| judge: parent qwen3-coder-30b ≤ 1 | 86 | 1 | 1 | 100% | 9% |
| grounded or grader claude-haiku-5.5 ≤ 1 | 140 | 33 | 7 | 21% | 58% |
| grounded or grader deepseek-v4-flash-0731#off ≤ 1 | 58 | 11 | 2 | 18% | 25% |
| grounded or grader qwen3-coder-30b ≤ 1 | 89 | 15 | 3 | 20% | 27% |
| grounded or parent claude-haiku-5.5 ≤ 1 | 140 | 19 | 3 | 16% | 25% |
| grounded or parent deepseek-v4-flash-0731#off ≤ 1 | 137 | 19 | 4 | 21% | 44% |
| grounded or parent qwen3-coder-30b ≤ 1 | 86 | 7 | 1 | 14% | 9% |

### cf3a|openrouter:anthropic/claude-haiku-5.5

140 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 4 | 0 | 0% | 0% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 1 | 0 | 0% | 0% |
| stopped early | 140 | 0 | 0 | – | 0% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 0 | 0 | – | 0% |
| repeated a call | 140 | 0 | 0 | – | 0% |
| any grounded signal | 140 | 5 | 0 | 0% | 0% |

### cf3a|openrouter:anthropic/claude-haiku-5.5#off

140 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 5 | 0 | 0% | 0% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 5 | 0 | 0% | 0% |
| stopped early | 140 | 0 | 0 | – | 0% |
| its last check failed | 140 | 1 | 0 | 0% | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 0 | 0 | – | 0% |
| repeated a call | 140 | 0 | 0 | – | 0% |
| any grounded signal | 140 | 8 | 0 | 0% | 0% |

### cf3a|openrouter:bytedance-seed/seed-2.0-mini

42 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 4 | 0 | 0% | 0% |
| the re-run check failed | 42 | 0 | 0 | – | 0% |
| a hard failure | 42 | 0 | 0 | – | 0% |
| stopped early | 42 | 0 | 0 | – | 0% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 0 | 0 | – | 0% |
| repeated a call | 42 | 4 | 0 | 0% | 0% |
| any grounded signal | 42 | 4 | 0 | 0% | 0% |

### cf3a|openrouter:deepseek/deepseek-v4-flash

140 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 4 | 0 | 0% | 0% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 2 | 0 | 0% | 0% |
| stopped early | 140 | 0 | 0 | – | 0% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 0 | 0 | – | 0% |
| repeated a call | 140 | 12 | 0 | 0% | 0% |
| any grounded signal | 140 | 6 | 0 | 0% | 0% |

### cf3a|openrouter:deepseek/deepseek-v4-flash#off

140 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 4 | 0 | 0% | 0% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 4 | 0 | 0% | 0% |
| stopped early | 140 | 0 | 0 | – | 0% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 0 | 0 | – | 0% |
| repeated a call | 140 | 9 | 0 | 0% | 0% |
| any grounded signal | 140 | 8 | 0 | 0% | 0% |

### cf3a|openrouter:deepseek/deepseek-v4-flash-0731

140 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 1 | 1 | 100% | 25% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 3 | 1 | 33% | 25% |
| stopped early | 140 | 1 | 1 | 100% | 25% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 1 | 1 | 100% | 25% |
| repeated a call | 140 | 4 | 0 | 0% | 0% |
| any grounded signal | 140 | 3 | 1 | 33% | 25% |

### cf3a|openrouter:deepseek/deepseek-v4-flash-0731#off

140 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 5 | 1 | 20% | 100% |
| the re-run check failed | 140 | 1 | 1 | 100% | 100% |
| a hard failure | 140 | 12 | 0 | 0% | 0% |
| stopped early | 140 | 1 | 1 | 100% | 100% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 1 | 0 | 0% | 0% |
| repeated a call | 140 | 12 | 0 | 0% | 0% |
| any grounded signal | 140 | 17 | 1 | 6% | 100% |

### cf3a|openrouter:deepseek/deepseek-v4.1-flash

140 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 1 | 0 | 0% | 0% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 5 | 0 | 0% | 0% |
| stopped early | 140 | 0 | 0 | – | 0% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 0 | 0 | – | 0% |
| repeated a call | 140 | 12 | 1 | 8% | 50% |
| any grounded signal | 140 | 5 | 0 | 0% | 0% |

### cf3a|openrouter:deepseek/deepseek-v4.1-flash#off

42 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | 0% |
| the re-run check failed | 42 | 0 | 0 | – | 0% |
| a hard failure | 42 | 1 | 0 | 0% | 0% |
| stopped early | 42 | 0 | 0 | – | 0% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 0 | 0 | – | 0% |
| repeated a call | 42 | 2 | 0 | 0% | 0% |
| any grounded signal | 42 | 1 | 0 | 0% | 0% |

### cf3a|openrouter:inception/mercury-2.5

140 runs, 12 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 8 | 0 | 0% | 0% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 6 | 1 | 17% | 8% |
| stopped early | 140 | 0 | 0 | – | 0% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 0 | 0 | – | 0% |
| repeated a call | 140 | 21 | 1 | 5% | 8% |
| any grounded signal | 140 | 14 | 1 | 7% | 8% |
| judge: grader claude-haiku-5.5 ≤ 1 | 140 | 29 | 7 | 24% | 58% |
| judge: grader deepseek-v4-flash-0731#off ≤ 1 | 58 | 9 | 2 | 22% | 25% |
| judge: grader qwen3-coder-30b ≤ 1 | 89 | 14 | 3 | 21% | 27% |
| judge: parent claude-haiku-5.5 ≤ 1 | 140 | 9 | 3 | 33% | 25% |
| judge: parent deepseek-v4-flash-0731#off ≤ 1 | 137 | 6 | 4 | 67% | 44% |
| judge: parent qwen3-coder-30b ≤ 1 | 86 | 1 | 1 | 100% | 9% |
| grounded or grader claude-haiku-5.5 ≤ 1 | 140 | 33 | 7 | 21% | 58% |
| grounded or grader deepseek-v4-flash-0731#off ≤ 1 | 58 | 11 | 2 | 18% | 25% |
| grounded or grader qwen3-coder-30b ≤ 1 | 89 | 15 | 3 | 20% | 27% |
| grounded or parent claude-haiku-5.5 ≤ 1 | 140 | 19 | 3 | 16% | 25% |
| grounded or parent deepseek-v4-flash-0731#off ≤ 1 | 137 | 19 | 4 | 21% | 44% |
| grounded or parent qwen3-coder-30b ≤ 1 | 86 | 7 | 1 | 14% | 9% |

### cf3a|openrouter:inception/mercury-3

140 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 2 | 0 | 0% | 0% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 8 | 0 | 0% | 0% |
| stopped early | 140 | 0 | 0 | – | 0% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 0 | 0 | – | 0% |
| repeated a call | 140 | 21 | 1 | 5% | 25% |
| any grounded signal | 140 | 10 | 0 | 0% | 0% |

### cf3a|openrouter:inception/mercury-3#off

42 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | 0% |
| the re-run check failed | 42 | 0 | 0 | – | 0% |
| a hard failure | 42 | 5 | 0 | 0% | 0% |
| stopped early | 42 | 0 | 0 | – | 0% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 0 | 0 | – | 0% |
| repeated a call | 42 | 9 | 1 | 11% | 50% |
| any grounded signal | 42 | 5 | 0 | 0% | 0% |

### cf3a|openrouter:inclusionai/ling-3.0-flash

140 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 1 | 0 | 0% | 0% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 5 | 0 | 0% | 0% |
| stopped early | 140 | 1 | 0 | 0% | 0% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 1 | 0 | 0% | 0% |
| changed files it didn't mention | 140 | 3 | 0 | 0% | 0% |
| repeated a call | 140 | 28 | 0 | 0% | 0% |
| any grounded signal | 140 | 5 | 0 | 0% | 0% |

### cf3a|openrouter:inclusionai/ling-3.1-flash

42 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 1 | 1 | 100% | 50% |
| the re-run check failed | 42 | 1 | 1 | 100% | 50% |
| a hard failure | 42 | 3 | 1 | 33% | 50% |
| stopped early | 42 | 0 | 0 | – | 0% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 0 | 0 | – | 0% |
| repeated a call | 42 | 3 | 0 | 0% | 0% |
| any grounded signal | 42 | 3 | 1 | 33% | 50% |

### cf3a|openrouter:inclusionai/ling-3.1-flash#off

42 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | 0% |
| the re-run check failed | 42 | 0 | 0 | – | 0% |
| a hard failure | 42 | 2 | 0 | 0% | 0% |
| stopped early | 42 | 0 | 0 | – | 0% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 0 | 0 | – | 0% |
| repeated a call | 42 | 6 | 1 | 17% | 100% |
| any grounded signal | 42 | 2 | 0 | 0% | 0% |

### cf3a|openrouter:liquid/lfm-2.5-24b-a2b

42 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 6 | 2 | 33% | 50% |
| the re-run check failed | 42 | 1 | 1 | 100% | 25% |
| a hard failure | 42 | 3 | 1 | 33% | 25% |
| stopped early | 42 | 3 | 1 | 33% | 25% |
| its last check failed | 42 | 1 | 0 | 0% | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 2 | 0 | 0% | 0% |
| repeated a call | 42 | 6 | 0 | 0% | 0% |
| any grounded signal | 42 | 6 | 2 | 33% | 50% |

### cf3a|openrouter:openai/gpt-6-luna-pro

42 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | – |
| the re-run check failed | 42 | 0 | 0 | – | – |
| a hard failure | 42 | 0 | 0 | – | – |
| stopped early | 42 | 0 | 0 | – | – |
| its last check failed | 42 | 0 | 0 | – | – |
| unfinished todos | 42 | 0 | 0 | – | – |
| changed files it didn't mention | 42 | 3 | 0 | 0% | – |
| repeated a call | 42 | 0 | 0 | – | – |
| any grounded signal | 42 | 0 | 0 | – | – |

### cf3a|openrouter:poolside/laguna-s-2.1#off

140 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 0 | 0 | – | 0% |
| the re-run check failed | 140 | 0 | 0 | – | 0% |
| a hard failure | 140 | 14 | 0 | 0% | 0% |
| stopped early | 140 | 0 | 0 | – | 0% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 0 | 0 | – | 0% |
| changed files it didn't mention | 140 | 0 | 0 | – | 0% |
| repeated a call | 140 | 24 | 1 | 4% | 50% |
| any grounded signal | 140 | 14 | 0 | 0% | 0% |

### cf3a|openrouter:poolside/laguna-xs-2.1

42 runs, 2 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 1 | 0 | 0% | 0% |
| the re-run check failed | 42 | 0 | 0 | – | 0% |
| a hard failure | 42 | 2 | 0 | 0% | 0% |
| stopped early | 42 | 0 | 0 | – | 0% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 0 | 0 | – | 0% |
| repeated a call | 42 | 6 | 0 | 0% | 0% |
| any grounded signal | 42 | 3 | 0 | 0% | 0% |

### cf3a|openrouter:prism-ml/ternary-bonsai-2-27b

42 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 3 | 3 | 100% | 60% |
| the re-run check failed | 42 | 1 | 1 | 100% | 20% |
| a hard failure | 42 | 7 | 5 | 71% | 100% |
| stopped early | 42 | 2 | 2 | 100% | 40% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 1 | 0 | 0% | 0% |
| changed files it didn't mention | 42 | 2 | 2 | 100% | 40% |
| repeated a call | 42 | 3 | 0 | 0% | 0% |
| any grounded signal | 42 | 8 | 5 | 63% | 100% |

### cf3a|openrouter:qwen/qwen3.5-flash-02-23

42 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 2 | 0 | 0% | 0% |
| the re-run check failed | 42 | 1 | 1 | 100% | 25% |
| a hard failure | 42 | 7 | 0 | 0% | 0% |
| stopped early | 42 | 0 | 0 | – | 0% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 0 | 0 | – | 0% |
| repeated a call | 42 | 3 | 0 | 0% | 0% |
| any grounded signal | 42 | 10 | 1 | 10% | 25% |

### cf3a|openrouter:qwen/qwen3.7-flash

42 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 2 | 0 | 0% | – |
| the re-run check failed | 42 | 0 | 0 | – | – |
| a hard failure | 42 | 1 | 0 | 0% | – |
| stopped early | 42 | 0 | 0 | – | – |
| its last check failed | 42 | 0 | 0 | – | – |
| unfinished todos | 42 | 0 | 0 | – | – |
| changed files it didn't mention | 42 | 0 | 0 | – | – |
| repeated a call | 42 | 5 | 0 | 0% | – |
| any grounded signal | 42 | 3 | 0 | 0% | – |

### cf3a|openrouter:stepfun/step-3.5-flash

140 runs, 6 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 140 | 14 | 3 | 21% | 50% |
| the re-run check failed | 140 | 1 | 1 | 100% | 17% |
| a hard failure | 140 | 15 | 4 | 27% | 67% |
| stopped early | 140 | 7 | 4 | 57% | 67% |
| its last check failed | 140 | 0 | 0 | – | 0% |
| unfinished todos | 140 | 6 | 3 | 50% | 50% |
| changed files it didn't mention | 140 | 7 | 2 | 29% | 33% |
| repeated a call | 140 | 20 | 0 | 0% | 0% |
| any grounded signal | 140 | 23 | 4 | 17% | 67% |

### cf3a|openrouter:xiaomi/mimo-v2.6-flash

42 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | 0% |
| the re-run check failed | 42 | 0 | 0 | – | 0% |
| a hard failure | 42 | 0 | 0 | – | 0% |
| stopped early | 42 | 0 | 0 | – | 0% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 0 | 0 | – | 0% |
| repeated a call | 42 | 7 | 1 | 14% | 100% |
| any grounded signal | 42 | 0 | 0 | – | 0% |

### cf3a|openrouter:z-ai/glm-4.7-flash

42 runs, 5 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 4 | 0 | 0% | 0% |
| the re-run check failed | 42 | 0 | 0 | – | 0% |
| a hard failure | 42 | 1 | 0 | 0% | 0% |
| stopped early | 42 | 0 | 0 | – | 0% |
| its last check failed | 42 | 0 | 0 | – | 0% |
| unfinished todos | 42 | 0 | 0 | – | 0% |
| changed files it didn't mention | 42 | 1 | 0 | 0% | 0% |
| repeated a call | 42 | 8 | 1 | 13% | 20% |
| any grounded signal | 42 | 5 | 0 | 0% | 0% |

### cf3b|*

210 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 210 | 0 | 0 | – | – |
| the re-run check failed | 210 | 0 | 0 | – | – |
| a hard failure | 210 | 0 | 0 | – | – |
| stopped early | 210 | 0 | 0 | – | – |
| its last check failed | 210 | 0 | 0 | – | – |
| unfinished todos | 210 | 0 | 0 | – | – |
| changed files it didn't mention | 210 | 0 | 0 | – | – |
| repeated a call | 210 | 13 | 0 | 0% | – |
| any grounded signal | 210 | 0 | 0 | – | – |

### cf3b|openrouter:anthropic/claude-opus-5.5

42 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | – |
| the re-run check failed | 42 | 0 | 0 | – | – |
| a hard failure | 42 | 0 | 0 | – | – |
| stopped early | 42 | 0 | 0 | – | – |
| its last check failed | 42 | 0 | 0 | – | – |
| unfinished todos | 42 | 0 | 0 | – | – |
| changed files it didn't mention | 42 | 0 | 0 | – | – |
| repeated a call | 42 | 0 | 0 | – | – |
| any grounded signal | 42 | 0 | 0 | – | – |

### cf3b|openrouter:anthropic/claude-sonnet-5.5

42 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | – |
| the re-run check failed | 42 | 0 | 0 | – | – |
| a hard failure | 42 | 0 | 0 | – | – |
| stopped early | 42 | 0 | 0 | – | – |
| its last check failed | 42 | 0 | 0 | – | – |
| unfinished todos | 42 | 0 | 0 | – | – |
| changed files it didn't mention | 42 | 0 | 0 | – | – |
| repeated a call | 42 | 2 | 0 | 0% | – |
| any grounded signal | 42 | 0 | 0 | – | – |

### cf3b|openrouter:google/gemini-4-argon

42 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | – |
| the re-run check failed | 42 | 0 | 0 | – | – |
| a hard failure | 42 | 0 | 0 | – | – |
| stopped early | 42 | 0 | 0 | – | – |
| its last check failed | 42 | 0 | 0 | – | – |
| unfinished todos | 42 | 0 | 0 | – | – |
| changed files it didn't mention | 42 | 0 | 0 | – | – |
| repeated a call | 42 | 5 | 0 | 0% | – |
| any grounded signal | 42 | 0 | 0 | – | – |

### cf3b|openrouter:moonshotai/kimi-k3.1-pro

42 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | – |
| the re-run check failed | 42 | 0 | 0 | – | – |
| a hard failure | 42 | 0 | 0 | – | – |
| stopped early | 42 | 0 | 0 | – | – |
| its last check failed | 42 | 0 | 0 | – | – |
| unfinished todos | 42 | 0 | 0 | – | – |
| changed files it didn't mention | 42 | 0 | 0 | – | – |
| repeated a call | 42 | 5 | 0 | 0% | – |
| any grounded signal | 42 | 0 | 0 | – | – |

### cf3b|openrouter:openai/gpt-5.6-sol

42 runs, 0 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 42 | 0 | 0 | – | – |
| the re-run check failed | 42 | 0 | 0 | – | – |
| a hard failure | 42 | 0 | 0 | – | – |
| stopped early | 42 | 0 | 0 | – | – |
| its last check failed | 42 | 0 | 0 | – | – |
| unfinished todos | 42 | 0 | 0 | – | – |
| changed files it didn't mention | 42 | 0 | 0 | – | – |
| repeated a call | 42 | 1 | 0 | 0% | – |
| any grounded signal | 42 | 0 | 0 | – | – |

### cf6|*

1439 runs, 14 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 1439 | 19 | 3 | 16% | 21% |
| the re-run check failed | 1439 | 2 | 2 | 100% | 14% |
| a hard failure | 1439 | 47 | 2 | 4% | 14% |
| stopped early | 1439 | 8 | 2 | 25% | 14% |
| its last check failed | 1439 | 0 | 0 | – | 0% |
| unfinished todos | 1439 | 7 | 2 | 29% | 14% |
| changed files it didn't mention | 1439 | 10 | 1 | 10% | 7% |
| repeated a call | 1439 | 120 | 1 | 1% | 7% |
| any grounded signal | 1439 | 59 | 3 | 5% | 21% |

### cf6|openrouter:anthropic/claude-haiku-5.5

480 runs, 4 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 480 | 9 | 0 | 0% | 0% |
| the re-run check failed | 480 | 0 | 0 | – | 0% |
| a hard failure | 480 | 12 | 0 | 0% | 0% |
| stopped early | 480 | 0 | 0 | – | 0% |
| its last check failed | 480 | 0 | 0 | – | 0% |
| unfinished todos | 480 | 0 | 0 | – | 0% |
| changed files it didn't mention | 480 | 0 | 0 | – | 0% |
| repeated a call | 480 | 32 | 0 | 0% | 0% |
| any grounded signal | 480 | 21 | 0 | 0% | 0% |

### cf6|openrouter:deepseek/deepseek-v4-flash-0731#off

480 runs, 1 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 480 | 2 | 1 | 50% | 100% |
| the re-run check failed | 480 | 1 | 1 | 100% | 100% |
| a hard failure | 480 | 21 | 0 | 0% | 0% |
| stopped early | 480 | 0 | 0 | – | 0% |
| its last check failed | 480 | 0 | 0 | – | 0% |
| unfinished todos | 480 | 0 | 0 | – | 0% |
| changed files it didn't mention | 480 | 0 | 0 | – | 0% |
| repeated a call | 480 | 42 | 1 | 2% | 100% |
| any grounded signal | 480 | 23 | 1 | 4% | 100% |

### cf6|openrouter:inclusionai/ling-3.0-flash

479 runs, 9 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 479 | 8 | 2 | 25% | 22% |
| the re-run check failed | 479 | 1 | 1 | 100% | 11% |
| a hard failure | 479 | 14 | 2 | 14% | 22% |
| stopped early | 479 | 8 | 2 | 25% | 22% |
| its last check failed | 479 | 0 | 0 | – | 0% |
| unfinished todos | 479 | 7 | 2 | 29% | 22% |
| changed files it didn't mention | 479 | 10 | 1 | 10% | 11% |
| repeated a call | 479 | 46 | 0 | 0% | 0% |
| any grounded signal | 479 | 15 | 2 | 13% | 22% |

### p1-after|*

96 runs, 11 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 96 | 1 | 1 | 100% | 9% |
| the re-run check failed | 96 | 0 | 0 | – | 0% |
| a hard failure | 96 | 5 | 4 | 80% | 36% |
| stopped early | 96 | 3 | 3 | 100% | 27% |
| its last check failed | 96 | 0 | 0 | – | 0% |
| unfinished todos | 96 | 1 | 1 | 100% | 9% |
| changed files it didn't mention | 96 | 3 | 1 | 33% | 9% |
| repeated a call | 96 | 21 | 3 | 14% | 27% |
| any grounded signal | 96 | 5 | 4 | 80% | 36% |

### p1-after|lmstudio:google/gemma-4-26b-a4b-qat

96 runs, 11 gold failures.

| trigger | runs it applies to | fires | failures it catches | precision | recall |
|---|---|---|---|---|---|
| the card's check failed | 96 | 1 | 1 | 100% | 9% |
| the re-run check failed | 96 | 0 | 0 | – | 0% |
| a hard failure | 96 | 5 | 4 | 80% | 36% |
| stopped early | 96 | 3 | 3 | 100% | 27% |
| its last check failed | 96 | 0 | 0 | – | 0% |
| unfinished todos | 96 | 1 | 1 | 100% | 9% |
| changed files it didn't mention | 96 | 3 | 1 | 33% | 9% |
| repeated a call | 96 | 21 | 3 | 14% | 27% |
| any grounded signal | 96 | 5 | 4 | 80% | 36% |

### cf6|openrouter:inclusionai/ling-3.0-flash>cf6|openrouter:anthropic/claude-haiku-5.5

| trigger | escalated from the first | of them needed | needed, missed | passed | a run | a success | seconds a run |
|---|---|---|---|---|---|---|---|
| never (the first model alone) | 0 | 0 | 9 | 470/479 (98%) | $0.00025 | $0.00026 | 17 |
| the card's check failed | 8 | 2 | 7 | 472/479 (99%) | $0.00031 | $0.00031 | 17 |
| the re-run check failed | 1 | 1 | 8 | 471/479 (98%) | $0.00026 | $0.00026 | 17 |
| a hard failure | 14 | 2 | 7 | 472/479 (99%) | $0.00036 | $0.00036 | 18 |
| stopped early | 8 | 2 | 7 | 472/479 (99%) | $0.00031 | $0.00032 | 17 |
| its last check failed | 0 | 0 | 9 | 470/479 (98%) | $0.00025 | $0.00026 | 17 |
| unfinished todos | 7 | 2 | 7 | 472/479 (99%) | $0.00031 | $0.00031 | 17 |
| changed files it didn't mention | 10 | 1 | 8 | 471/479 (98%) | $0.00032 | $0.00032 | 17 |
| repeated a call | 46 | 0 | 9 | 470/479 (98%) | $0.00045 | $0.00046 | 19 |
| any grounded signal | 15 | 2 | 7 | 472/479 (99%) | $0.00036 | $0.00037 | 18 |
| oracle (exactly the failures) | 9 | 9 | 0 | 479/479 (100%) | $0.00028 | $0.00028 | 17 |
| always (up to the top) | 479 | 9 | 0 | 475/479 (99%) | $0.00170 | $0.00171 | 34 |
| **the top model alone** | – | – | – | 475/479 (99%) | $0.00144 | $0.00146 | 17 |

### cf3a|openrouter:inception/mercury-2.5>cf3a|openrouter:anthropic/claude-haiku-5.5

| trigger | escalated from the first | of them needed | needed, missed | passed | a run | a success | seconds a run |
|---|---|---|---|---|---|---|---|
| never (the first model alone) | 0 | 0 | 12 | 128/140 (91%) | $0.00087 | $0.00095 | 18 |
| the card's check failed | 8 | 0 | 12 | 128/140 (91%) | $0.00103 | $0.00112 | 19 |
| the re-run check failed | 0 | 0 | 12 | 128/140 (91%) | $0.00087 | $0.00095 | 18 |
| a hard failure | 6 | 1 | 11 | 129/140 (92%) | $0.00094 | $0.00102 | 19 |
| stopped early | 0 | 0 | 12 | 128/140 (91%) | $0.00087 | $0.00095 | 18 |
| its last check failed | 0 | 0 | 12 | 128/140 (91%) | $0.00087 | $0.00095 | 18 |
| unfinished todos | 0 | 0 | 12 | 128/140 (91%) | $0.00087 | $0.00095 | 18 |
| changed files it didn't mention | 0 | 0 | 12 | 128/140 (91%) | $0.00087 | $0.00095 | 18 |
| repeated a call | 21 | 1 | 11 | 129/140 (92%) | $0.00112 | $0.00121 | 21 |
| any grounded signal | 14 | 1 | 11 | 129/140 (92%) | $0.00109 | $0.00118 | 20 |
| judge: grader claude-haiku-5.5 ≤ 1 | 29 | 7 | 5 | 134/140 (96%) | $0.00171 | $0.00178 | 22 |
| judge: grader deepseek-v4-flash-0731#off ≤ 1 | 9 | 2 | 10 | 130/140 (93%) | $0.00108 | $0.00117 | 19 |
| judge: grader qwen3-coder-30b ≤ 1 | 14 | 3 | 9 | 131/140 (94%) | $0.00115 | $0.00123 | 20 |
| judge: parent claude-haiku-5.5 ≤ 1 | 9 | 3 | 9 | 131/140 (94%) | $0.00255 | $0.00273 | 20 |
| judge: parent deepseek-v4-flash-0731#off ≤ 1 | 6 | 4 | 8 | 132/140 (94%) | $0.00140 | $0.00149 | 19 |
| judge: parent qwen3-coder-30b ≤ 1 | 1 | 1 | 11 | 129/140 (92%) | $0.00092 | $0.00100 | 18 |
| grounded or grader claude-haiku-5.5 ≤ 1 | 33 | 7 | 5 | 134/140 (96%) | $0.00176 | $0.00184 | 23 |
| grounded or grader deepseek-v4-flash-0731#off ≤ 1 | 20 | 2 | 10 | 130/140 (93%) | $0.00126 | $0.00136 | 21 |
| grounded or grader qwen3-coder-30b ≤ 1 | 22 | 4 | 8 | 132/140 (94%) | $0.00124 | $0.00132 | 21 |
| grounded or parent claude-haiku-5.5 ≤ 1 | 19 | 3 | 9 | 131/140 (94%) | $0.00269 | $0.00287 | 21 |
| grounded or parent deepseek-v4-flash-0731#off ≤ 1 | 19 | 4 | 8 | 132/140 (94%) | $0.00162 | $0.00171 | 21 |
| grounded or parent qwen3-coder-30b ≤ 1 | 15 | 2 | 10 | 130/140 (93%) | $0.00114 | $0.00122 | 20 |
| oracle (exactly the failures) | 12 | 12 | 0 | 139/140 (99%) | $0.00104 | $0.00104 | 20 |
| always (up to the top) | 140 | 12 | 0 | 139/140 (99%) | $0.00241 | $0.00243 | 37 |
| **the top model alone** | – | – | – | 139/140 (99%) | $0.00154 | $0.00155 | 19 |

### cf3a|openrouter:inception/mercury-2.5>cf3a|openrouter:anthropic/claude-haiku-5.5>cf3b|openrouter:anthropic/claude-opus-5.5

| trigger | escalated from the first | of them needed | needed, missed | passed | a run | a success | seconds a run |
|---|---|---|---|---|---|---|---|
| never (the first model alone) | 0 | 0 | 3 | 39/42 (93%) | $0.00087 | $0.00094 | 17 |
| the card's check failed | 1 | 0 | 3 | 39/42 (93%) | $0.00091 | $0.00098 | 18 |
| the re-run check failed | 0 | 0 | 3 | 39/42 (93%) | $0.00087 | $0.00094 | 17 |
| a hard failure | 1 | 0 | 3 | 39/42 (93%) | $0.00089 | $0.00096 | 18 |
| stopped early | 0 | 0 | 3 | 39/42 (93%) | $0.00087 | $0.00094 | 17 |
| its last check failed | 0 | 0 | 3 | 39/42 (93%) | $0.00087 | $0.00094 | 17 |
| unfinished todos | 0 | 0 | 3 | 39/42 (93%) | $0.00087 | $0.00094 | 17 |
| changed files it didn't mention | 0 | 0 | 3 | 39/42 (93%) | $0.00087 | $0.00094 | 17 |
| repeated a call | 6 | 1 | 2 | 40/42 (95%) | $0.00108 | $0.00114 | 20 |
| any grounded signal | 2 | 0 | 3 | 39/42 (93%) | $0.00093 | $0.00100 | 18 |
| judge: grader claude-haiku-5.5 ≤ 1 | 8 | 3 | 0 | 41/42 (98%) | $0.00155 | $0.00158 | 21 |
| judge: grader deepseek-v4-flash-0731#off ≤ 1 | 2 | 0 | 3 | 39/42 (93%) | $0.00098 | $0.00105 | 18 |
| judge: grader qwen3-coder-30b ≤ 1 | 1 | 1 | 2 | 40/42 (95%) | $0.00089 | $0.00093 | 18 |
| judge: parent claude-haiku-5.5 ≤ 1 | 2 | 0 | 3 | 39/42 (93%) | $0.00247 | $0.00266 | 19 |
| judge: parent deepseek-v4-flash-0731#off ≤ 1 | 1 | 0 | 3 | 39/42 (93%) | $0.00138 | $0.00149 | 18 |
| judge: parent qwen3-coder-30b ≤ 1 | 0 | 0 | 3 | 39/42 (93%) | $0.00087 | $0.00094 | 17 |
| grounded or grader claude-haiku-5.5 ≤ 1 | 9 | 3 | 0 | 41/42 (98%) | $0.00158 | $0.00162 | 21 |
| grounded or grader deepseek-v4-flash-0731#off ≤ 1 | 4 | 0 | 3 | 39/42 (93%) | $0.00104 | $0.00112 | 19 |
| grounded or grader qwen3-coder-30b ≤ 1 | 3 | 1 | 2 | 40/42 (95%) | $0.00095 | $0.00099 | 19 |
| grounded or parent claude-haiku-5.5 ≤ 1 | 4 | 0 | 3 | 39/42 (93%) | $0.00253 | $0.00273 | 19 |
| grounded or parent deepseek-v4-flash-0731#off ≤ 1 | 3 | 0 | 3 | 39/42 (93%) | $0.00144 | $0.00155 | 19 |
| grounded or parent qwen3-coder-30b ≤ 1 | 2 | 0 | 3 | 39/42 (93%) | $0.00093 | $0.00100 | 18 |
| oracle (exactly the failures) | 3 | 3 | 0 | 42/42 (100%) | $0.00144 | $0.00144 | 19 |
| always (up to the top) | 42 | 3 | 0 | 42/42 (100%) | $0.048 | $0.048 | 61 |
| **the top model alone** | – | – | – | 42/42 (100%) | $0.046 | $0.046 | 26 |

### p1-after|lmstudio:google/gemma-4-26b-a4b-qat>cf6|openrouter:inclusionai/ling-3.0-flash>cf6|openrouter:anthropic/claude-haiku-5.5

| trigger | escalated from the first | of them needed | needed, missed | passed | a run | a success | seconds a run |
|---|---|---|---|---|---|---|---|
| never (the first model alone) | 0 | 0 | 11 | 85/96 (89%) | $0 | $0 | 46 |
| the card's check failed | 1 | 1 | 10 | 86/96 (90%) | $0.00001 | $0.00001 | 47 |
| the re-run check failed | 0 | 0 | 11 | 85/96 (89%) | $0 | $0 | 46 |
| a hard failure | 5 | 4 | 7 | 89/96 (93%) | $0.00002 | $0.00002 | 47 |
| stopped early | 3 | 3 | 8 | 88/96 (92%) | $0.00001 | $0.00001 | 47 |
| its last check failed | 0 | 0 | 11 | 85/96 (89%) | $0 | $0 | 46 |
| unfinished todos | 1 | 1 | 10 | 86/96 (90%) | $0.00001 | $0.00001 | 47 |
| changed files it didn't mention | 3 | 1 | 10 | 86/96 (90%) | $0.00002 | $0.00002 | 47 |
| repeated a call | 21 | 3 | 8 | 88/96 (92%) | $0.00028 | $0.00030 | 53 |
| any grounded signal | 5 | 4 | 7 | 89/96 (93%) | $0.00002 | $0.00002 | 47 |
| oracle (exactly the failures) | 11 | 11 | 0 | 96/96 (100%) | $0.00004 | $0.00004 | 48 |
| always (up to the top) | 96 | 11 | 0 | 96/96 (100%) | $0.00173 | $0.00173 | 81 |
| **the top model alone** | – | – | – | 96/96 (100%) | $0.00147 | $0.00147 | 17 |

### bank1|lmstudio:google/gemma-4-26b-a4b-qat>cf6|openrouter:inclusionai/ling-3.0-flash>cf6|openrouter:anthropic/claude-haiku-5.5

| trigger | escalated from the first | of them needed | needed, missed | passed | a run | a success | seconds a run |
|---|---|---|---|---|---|---|---|
| never (the first model alone) | 0 | 0 | 11 | 91/102 (89%) | $0 | $0 | 58 |
| the card's check failed | 0 | 0 | 11 | 91/102 (89%) | $0 | $0 | 58 |
| the re-run check failed | 0 | 0 | 11 | 91/102 (89%) | $0 | $0 | 58 |
| a hard failure | 4 | 3 | 8 | 94/102 (92%) | $0.00000 | $0.00000 | 58 |
| stopped early | 5 | 3 | 8 | 94/102 (92%) | $0.00001 | $0.00001 | 58 |
| its last check failed | 0 | 0 | 11 | 91/102 (89%) | $0 | $0 | 58 |
| unfinished todos | 0 | 0 | 11 | 91/102 (89%) | $0 | $0 | 58 |
| changed files it didn't mention | 3 | 0 | 11 | 91/102 (89%) | $0.00002 | $0.00002 | 58 |
| repeated a call | 14 | 0 | 11 | 91/102 (89%) | $0.00016 | $0.00018 | 61 |
| any grounded signal | 5 | 3 | 8 | 94/102 (92%) | $0.00001 | $0.00001 | 58 |
| judge: grader gemini-3.8-flash ≤ 1 | 2 | 2 | 9 | 93/102 (91%) | $0.00063 | $0.00069 | 58 |
| judge: grader gemini-4-argon ≤ 1 | 2 | 1 | 10 | 92/102 (90%) | $0.00089 | $0.00098 | 58 |
| judge: grader gemma-4-26b-a4b-qat ≤ 1 | 2 | 2 | 9 | 93/102 (91%) | $0.00000 | $0.00000 | 58 |
| judge: grader qwen3.5-9b ≤ 1 | 8 | 2 | 9 | 93/102 (91%) | $0.00001 | $0.00001 | 59 |
| judge: parent gemini-3.8-flash ≤ 1 | 3 | 3 | 8 | 94/102 (92%) | $0.00333 | $0.00361 | 58 |
| judge: parent gemini-4-argon ≤ 1 | 3 | 3 | 8 | 94/102 (92%) | $0.00486 | $0.00527 | 58 |
| judge: parent gemma-4-26b-a4b-qat ≤ 1 | 0 | 0 | 11 | 91/102 (89%) | $0 | $0 | 58 |
| judge: parent qwen3.5-9b ≤ 1 | 3 | 2 | 9 | 93/102 (91%) | $0.00001 | $0.00001 | 58 |
| review: google-gemini:gemini-3.8-flash found a problem | 0 | 0 | 11 | 91/102 (89%) | $0.00008 | $0.00008 | 58 |
| review: lmstudio:qwen/qwen3-coder-30b found a problem | 0 | 0 | 11 | 91/102 (89%) | $0 | $0 | 58 |
| review: openrouter:anthropic/claude-haiku-5.5 found a problem | 3 | 2 | 9 | 93/102 (91%) | $0.00004 | $0.00004 | 58 |
| review: openrouter:deepseek/deepseek-v4-flash-0731#off found a problem | 0 | 0 | 11 | 91/102 (89%) | $0.00000 | $0.00000 | 58 |
| grounded or grader gemini-3.8-flash ≤ 1 | 6 | 4 | 7 | 95/102 (93%) | $0.00064 | $0.00068 | 59 |
| grounded or grader gemini-4-argon ≤ 1 | 6 | 3 | 8 | 94/102 (92%) | $0.00089 | $0.00097 | 59 |
| grounded or grader gemma-4-26b-a4b-qat ≤ 1 | 6 | 4 | 7 | 95/102 (93%) | $0.00001 | $0.00001 | 59 |
| grounded or grader qwen3.5-9b ≤ 1 | 12 | 4 | 7 | 95/102 (93%) | $0.00002 | $0.00002 | 60 |
| grounded or parent gemini-3.8-flash ≤ 1 | 7 | 5 | 6 | 96/102 (94%) | $0.00333 | $0.00354 | 59 |
| grounded or parent gemini-4-argon ≤ 1 | 7 | 5 | 6 | 96/102 (94%) | $0.00487 | $0.00517 | 59 |
| grounded or parent gemma-4-26b-a4b-qat ≤ 1 | 5 | 3 | 8 | 94/102 (92%) | $0.00001 | $0.00001 | 58 |
| grounded or parent qwen3.5-9b ≤ 1 | 7 | 4 | 7 | 95/102 (93%) | $0.00001 | $0.00001 | 59 |
| grounded or review google-gemini:gemini-3.8-flash | 5 | 3 | 8 | 94/102 (92%) | $0.00008 | $0.00009 | 58 |
| grounded or review lmstudio:qwen/qwen3-coder-30b | 5 | 3 | 8 | 94/102 (92%) | $0.00001 | $0.00001 | 58 |
| grounded or review openrouter:anthropic/claude-haiku-5.5 | 8 | 5 | 6 | 96/102 (94%) | $0.00005 | $0.00005 | 59 |
| grounded or review openrouter:deepseek/deepseek-v4-flash-0731#off | 5 | 3 | 8 | 94/102 (92%) | $0.00001 | $0.00001 | 58 |
| oracle (exactly the failures) | 11 | 11 | 0 | 102/102 (100%) | $0.00003 | $0.00003 | 60 |
| always (up to the top) | 102 | 11 | 0 | 102/102 (100%) | $0.00145 | $0.00145 | 89 |
| **the top model alone** | – | – | – | 102/102 (100%) | $0.00125 | $0.00125 | 16 |

