## The funnel

- Stage 1 screened 499 configurations: 105 never ran (every run an infrastructure failure), 335 passed at least 5 of 6.
- Stage 2 ran the whole bank on 232 of them.
- Stage 3a ran the hard tier on 25 finalists; stage 3b on 5 frontier references.

## Finalists: bank and hard tier together

Cost is list price per run, the mean over every run the configuration made; $/success = cost ÷ pass rate.

| configuration | bank | hard | all (95% CI) | $/run | $/success | mean s |
|---|---|---|---|---|---|---|
| inclusionai/ling-3.0-flash | 335/340 | 139/140 | 99% (97%–99%) | $0.00021 | $0.00022 | 19 |
| deepseek/deepseek-v4-flash-0731#off | 334/340 | 139/140 | 99% (97%–99%) | $0.00042 | $0.00042 | 16 |
| qwen/qwen3.7-flash | 94/102 | 42/42 | 94% (89%–97%) | $0.00041 | $0.00044 | 23 |
| deepseek/deepseek-v4-flash-0731 | 336/340 | 136/140 | 98% (97%–99%) | $0.00053 | $0.00054 | 18 |
| inception/mercury-2.5 | 327/340 | 128/140 | 95% (92%–96%) | $0.00059 | $0.00062 | 16 |
| inclusionai/ling-3.1-flash#off | 98/102 | 41/42 | 97% (92%–99%) | $0.00066 | $0.00069 | 92 |
| inclusionai/ling-3.1-flash | 97/102 | 40/42 | 95% (90%–98%) | $0.00069 | $0.00072 | 136 |
| poolside/laguna-s-2.1#off | 326/340 | 138/140 | 97% (95%–98%) | $0.00070 | $0.00073 | 19 |
| deepseek/deepseek-v4-flash#off | 331/340 | 136/140 | 97% (95%–98%) | $0.00079 | $0.00081 | 20 |
| deepseek/deepseek-v4-flash | 336/340 | 136/140 | 98% (97%–99%) | $0.00087 | $0.00088 | 22 |
| inception/mercury-3#off | 99/102 | 40/42 | 97% (92%–99%) | $0.00086 | $0.00089 | 13 |
| poolside/laguna-xs-2.1 | 95/102 | 40/42 | 94% (89%–97%) | $0.00089 | $0.00095 | 24 |
| inception/mercury-3 | 335/340 | 136/140 | 98% (96%–99%) | $0.00093 | $0.00095 | 14 |
| deepseek/deepseek-v4.1-flash#off | 100/102 | 41/42 | 98% (94%–99%) | $0.00104 | $0.00106 | 16 |
| anthropic/claude-haiku-5.5#off | 332/340 | 139/140 | 98% (96%–99%) | $0.00107 | $0.00109 | 16 |
| xiaomi/mimo-v2.6-flash | 99/102 | 41/42 | 97% (93%–99%) | $0.00109 | $0.00113 | 21 |
| anthropic/claude-haiku-5.5 | 339/340 | 139/140 | 100% (98%–100%) | $0.00113 | $0.00114 | 17 |
| z-ai/glm-4.7-flash | 96/102 | 37/42 | 92% (87%–96%) | $0.00119 | $0.00128 | 35 |
| qwen/qwen3.5-flash-02-23 | 98/102 | 38/42 | 94% (89%–97%) | $0.00139 | $0.00147 | 21 |
| prism-ml/ternary-bonsai-2-27b | 95/102 | 37/42 | 92% (86%–95%) | $0.00142 | $0.00155 | 111 |
| deepseek/deepseek-v4.1-flash | 325/340 | 138/140 | 96% (94%–98%) | $0.00181 | $0.00188 | 19 |
| stepfun/step-3.5-flash | 329/340 | 134/140 | 96% (94%–98%) | $0.00195 | $0.00202 | 36 |
| liquid/lfm-2.5-24b-a2b | 101/102 | 38/42 | 97% (92%–99%) | $0.00212 | $0.00220 | 15 |
| bytedance-seed/seed-2.0-mini | 93/102 | 41/42 | 93% (88%–96%) | $0.00209 | $0.00225 | 25 |
| openai/gpt-6-luna-pro | 93/102 | 42/42 | 94% (89%–97%) | $0.00282 | $0.00301 | 39 |

## References (hard tier only)

| model | hard (95% CI) | $/run | $/success | mean s |
|---|---|---|---|---|
| anthropic/claude-opus-5.5 | 42/42 (92%–100%) | $0.0458 | $0.0458 | 26 |
| anthropic/claude-sonnet-5.5 | 42/42 (92%–100%) | $0.0229 | $0.0229 | 19 |
| google/gemini-4-argon | 42/42 (92%–100%) | $0.0349 | $0.0349 | 36 |
| moonshotai/kimi-k3.1-pro | 42/42 (92%–100%) | $0.0287 | $0.0287 | 58 |
| openai/gpt-5.6-sol | 42/42 (92%–100%) | $0.0397 | $0.0397 | 29 |

## Cheapest above the floor

A configuration clears a floor when the lower bound of its 95% interval does (bank + hard runs together).

| floor | cheapest by $/success | rate (lower bound) | $/success | next two |
|---|---|---|---|---|
| 80% | inclusionai/ling-3.0-flash | 99% (97%) | $0.00022 | deepseek/deepseek-v4-flash-0731#off ($0.00042), qwen/qwen3.7-flash ($0.00044) |
| 90% | inclusionai/ling-3.0-flash | 99% (97%) | $0.00022 | deepseek/deepseek-v4-flash-0731#off ($0.00042), deepseek/deepseek-v4-flash-0731 ($0.00054) |
| 95% | inclusionai/ling-3.0-flash | 99% (97%) | $0.00022 | deepseek/deepseek-v4-flash-0731#off ($0.00042), deepseek/deepseek-v4-flash-0731 ($0.00054) |

By point estimate (no interval), the cheapest at each floor:

- 80%: inclusionai/ling-3.0-flash (99%, $0.00022 per success)
- 90%: inclusionai/ling-3.0-flash (99%, $0.00022 per success)
- 95%: inclusionai/ling-3.0-flash (99%, $0.00022 per success)

## By kind (top 8 finalists by $/success; estimates, not certified)

| configuration | edit | explain | fix | refactor | research | review | run | search | summarize | write-tests |
|---|---|---|---|---|---|---|---|---|---|---|
| inclusionai/ling-3.0-flash | 40/40 | 70/70 | 50/50 | 30/30 | 60/60 | 40/40 | 30/30 | 77/80 | 47/50 | 30/30 |
| deepseek/deepseek-v4-flash-0731#off | 39/40 | 70/70 | 50/50 | 30/30 | 60/60 | 40/40 | 30/30 | 79/80 | 45/50 | 30/30 |
| qwen/qwen3.7-flash | 12/12 | 19/21 | 14/15 | 9/9 | 17/18 | 12/12 | 9/9 | 21/24 | 14/15 | 9/9 |
| deepseek/deepseek-v4-flash-0731 | 36/40 | 69/70 | 50/50 | 30/30 | 60/60 | 40/40 | 30/30 | 77/80 | 50/50 | 30/30 |
| inception/mercury-2.5 | 39/40 | 70/70 | 50/50 | 30/30 | 57/60 | 38/40 | 29/30 | 62/80 | 50/50 | 30/30 |
| inclusionai/ling-3.1-flash#off | 11/12 | 20/21 | 15/15 | 9/9 | 18/18 | 12/12 | 9/9 | 22/24 | 14/15 | 9/9 |
| inclusionai/ling-3.1-flash | 11/12 | 20/21 | 15/15 | 9/9 | 17/18 | 12/12 | 9/9 | 21/24 | 15/15 | 8/9 |
| poolside/laguna-s-2.1#off | 38/40 | 70/70 | 50/50 | 30/30 | 59/60 | 38/40 | 30/30 | 77/80 | 42/50 | 30/30 |

## Reasoning off against default (stage 1 and 2 runs, configurations that ran both)

85 models ran the bank both ways; reasoning off was cheaper per success for 62 of them.

| model | default: rate, $/success | off: rate, $/success |
|---|---|---|
| inclusionai/ling-3.0-flash | 99%, $0.00018 | 88%, $0.00018 |
| qwen/qwen3.7-flash | 92%, $0.00036 | 91%, $0.00030 |
| deepseek/deepseek-v4-flash-0731 | 99%, $0.00040 | 98%, $0.00031 |
| inception/mercury-2.5 | 96%, $0.00049 | 91%, $0.00047 |
| poolside/laguna-s-2.1 | 94%, $0.00057 | 96%, $0.00056 |
| nex-agi/nex-n2.5-pro | 65%, $0.00057 | 79%, $0.00043 |
| inclusionai/ling-3.1-flash | 95%, $0.00062 | 96%, $0.00053 |
| deepseek/deepseek-v4-flash | 99%, $0.00069 | 97%, $0.00067 |
| openai/gpt-6-luna | 91%, $0.00073 | 82%, $0.00083 |
| upstage/solar-mini4 | 88%, $0.00076 | 91%, $0.00101 |
| inception/mercury-3 | 99%, $0.00077 | 97%, $0.00066 |
| poolside/laguna-xs-2.1 | 93%, $0.00080 | 94%, $0.00067 |
| tencent/hy3 | 94%, $0.00081 | 94%, $0.00072 |
| xiaomi/mimo-v2.6-flash | 97%, $0.00087 | 94%, $0.00163 |
| z-ai/glm-4.7-flash | 94%, $0.00092 | 88%, $0.00084 |

## Unreliable: infrastructure failures in stage 1

- 324 runs: reasoning can't be turned off
- 100 runs: no provider without training on prompts (404)
- 12 runs: rate limited (429)
- 8 runs: Server returned HTTP 400: Provider returned error
- 4 runs: The server reported an error: routing: framework forward exh
- 3 runs: The server reported an error: the server ended the reply wit

