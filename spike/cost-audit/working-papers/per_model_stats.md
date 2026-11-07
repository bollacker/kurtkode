# Per-model statistics computed directly from eval-results/runs (python3 -I, stdlib only)

Real runs only: degraded copies (`degradation`) and infrastructure failures (`infra`) excluded. List cost = run.json `listPrice` (missing for local/unpriced runs). Pass = `gold.passed`. Prompt tokens are the run total over all requests (cached included).

## Bank tier (cf2, cf6, bank1), per store and model

### bank

| store | model | runs | pass rate | mean list $/run | median list $/run | priced runs | mean prompt tok | mean output tok | mean steps |
|---|---|---|---|---|---|---|---|---|---|
| bank1 | google-gemini:gemini-3.6-flash | 102 | 102/102 (100.0%) | 0.01968 | 0.01613 | 102 | 19,850 | 1,322 | 7.3 |
| bank1 | google-gemini:gemini-3.8-flash | 102 | 102/102 (100.0%) | 0.01951 | 0.01232 | 102 | 19,846 | 1,198 | 7.3 |
| bank1 | google-gemini:gemini-4-argon | 102 | 102/102 (100.0%) | 0.02066 | 0.01505 | 102 | 8,181 | 514 | 3.6 |
| bank1 | lmstudio:google/gemma-4-26b-a4b-qat | 102 | 91/102 (89.2%) | – | – | 0 | 11,942 | 1,190 | 5.6 |
| bank1 | bang:qwen/qwen3.5-9b | 102 | 90/102 (88.2%) | – | – | 0 | 16,422 | 971 | 5.7 |
| bank1 | lmstudio:gemma-4-e4b-it | 102 | 83/102 (81.4%) | – | – | 0 | 11,525 | 1,878 | 5.0 |
| cf2 | openrouter:bytedance-seed/seed-2-1-turbo | 28 | 28/28 (100.0%) | 0.00697 | 0.00469 | 28 | 10,565 | 675 | 4.1 |
| cf2 | openrouter:bytedance-seed/seed-2-1-turbo#off | 28 | 28/28 (100.0%) | 0.00680 | 0.00310 | 28 | 11,415 | 438 | 4.2 |
| cf2 | openrouter:deepseek/deepseek-v3.2-exp | 28 | 28/28 (100.0%) | 0.01244 | 0.00518 | 28 | 43,957 | 1,404 | 10.5 |
| cf2 | openrouter:deepseek/deepseek-v4-flash-vision-exp#off | 28 | 28/28 (100.0%) | 0.00131 | 0.00095 | 28 | 10,725 | 601 | 3.8 |
| cf2 | openrouter:deepseek/deepseek-v4-pro | 28 | 28/28 (100.0%) | 0.00088 | 0.00071 | 28 | 7,890 | 773 | 3.5 |
| cf2 | openrouter:deepseek/deepseek-v4-pro-0813 | 28 | 28/28 (100.0%) | 0.00427 | 0.00300 | 28 | 8,543 | 557 | 3.5 |
| cf2 | openrouter:elorian/glimpse | 28 | 28/28 (100.0%) | 0.00747 | 0.00511 | 28 | 12,087 | 961 | 4.1 |
| cf2 | openrouter:meituan/longcat-2.0 | 28 | 28/28 (100.0%) | 0.00141 | 0.00111 | 28 | 7,549 | 667 | 3.5 |
| cf2 | openrouter:meituan/longcat-2.0#off | 28 | 28/28 (100.0%) | 0.00103 | 0.00055 | 28 | 8,381 | 295 | 3.6 |
| cf2 | openrouter:meta/muse-glimmer-30b | 28 | 28/28 (100.0%) | 0.00640 | 0.00398 | 28 | 35,171 | 1,979 | 8.6 |
| cf2 | openrouter:minimax/minimax-m3 | 28 | 28/28 (100.0%) | 0.00416 | 0.00165 | 28 | 15,585 | 1,584 | 4.9 |
| cf2 | openrouter:mistralai/mistral-large-4-0#off | 28 | 28/28 (100.0%) | 0.00600 | 0.00451 | 28 | 6,197 | 240 | 3.3 |
| cf2 | openrouter:moonshotai/kimi-k2-thinking | 28 | 28/28 (100.0%) | 0.00397 | 0.00259 | 28 | 6,429 | 648 | 3.4 |
| cf2 | openrouter:moonshotai/kimi-k2.5#off | 28 | 28/28 (100.0%) | 0.00407 | 0.00220 | 28 | 9,044 | 585 | 3.6 |
| cf2 | openrouter:moonshotai/kimi-k2.6 | 28 | 28/28 (100.0%) | 0.00443 | 0.00320 | 28 | 5,966 | 705 | 3.4 |
| cf2 | openrouter:moonshotai/kimi-k3 | 28 | 28/28 (100.0%) | 0.00829 | 0.00623 | 28 | 8,228 | 600 | 3.7 |
| cf2 | openrouter:moonshotai/kimi-k3#off | 28 | 28/28 (100.0%) | 0.00686 | 0.00565 | 28 | 8,351 | 465 | 3.7 |
| cf2 | openrouter:nvidia/nemotron-3-ultra-550b-a55b | 28 | 28/28 (100.0%) | 0.00562 | 0.00363 | 28 | 14,304 | 602 | 4.5 |
| cf2 | openrouter:nvidia/nemotron-3.5-super-vl | 28 | 28/28 (100.0%) | 0.00178 | 0.00111 | 28 | 11,507 | 850 | 3.5 |
| cf2 | openrouter:nvidia/nemotron-3.5-super-vl#off | 28 | 28/28 (100.0%) | 0.00123 | 0.00081 | 28 | 9,859 | 398 | 3.5 |
| cf2 | openrouter:qwen/qwen3-235b-a22b-thinking-2507 | 28 | 28/28 (100.0%) | 0.00661 | 0.00494 | 28 | 9,177 | 707 | 3.6 |
| cf2 | openrouter:qwen/qwen3.5-122b-a10b#off | 28 | 28/28 (100.0%) | 0.00617 | 0.00307 | 28 | 12,004 | 427 | 4.5 |
| cf2 | openrouter:qwen/qwen3.5-35b-a3b | 28 | 28/28 (100.0%) | 0.00267 | 0.00126 | 28 | 15,188 | 749 | 5.0 |
| cf2 | openrouter:qwen/qwen3.5-397b-a17b | 28 | 28/28 (100.0%) | 0.00596 | 0.00385 | 28 | 8,804 | 555 | 3.4 |
| cf2 | openrouter:qwen/qwen3.5-plus-02-15 | 28 | 28/28 (100.0%) | 0.00349 | 0.00215 | 28 | 9,863 | 594 | 3.8 |
| cf2 | openrouter:qwen/qwen3.5-plus-02-15#off | 28 | 28/28 (100.0%) | 0.00316 | 0.00169 | 28 | 9,802 | 391 | 3.5 |
| cf2 | openrouter:qwen/qwen3.5-plus-20260420 | 28 | 28/28 (100.0%) | 0.00324 | 0.00225 | 28 | 7,201 | 601 | 3.2 |
| cf2 | openrouter:qwen/qwen3.6-27b | 28 | 28/28 (100.0%) | 0.00309 | 0.00272 | 28 | 7,886 | 642 | 3.1 |
| cf2 | openrouter:qwen/qwen3.7-plus | 28 | 28/28 (100.0%) | 0.00212 | 0.00148 | 28 | 9,145 | 623 | 3.5 |
| cf2 | openrouter:reflection/beam-1.0-501b-a23b | 28 | 28/28 (100.0%) | 0.00239 | 0.00117 | 28 | 16,282 | 1,018 | 5.4 |
| cf2 | openrouter:tencent/hy3-preview | 28 | 28/28 (100.0%) | 0.00103 | 0.00085 | 28 | 7,221 | 532 | 3.5 |
| cf2 | openrouter:unbiased/pareto-26.10 | 28 | 28/28 (100.0%) | 0.00639 | 0.00510 | 28 | 8,281 | 624 | 3.9 |
| cf2 | openrouter:xiaomi/mimo-v2.6-pro | 28 | 28/28 (100.0%) | 0.00170 | 0.00130 | 28 | 7,315 | 812 | 3.7 |
| cf2 | openrouter:xiaomi/mimo-v2.6-pro#off | 28 | 28/28 (100.0%) | 0.00160 | 0.00139 | 28 | 9,666 | 419 | 4.6 |
| cf2 | openrouter:z-ai/glm-4.5 | 28 | 28/28 (100.0%) | 0.00356 | 0.00261 | 28 | 7,401 | 459 | 3.5 |
| cf2 | openrouter:z-ai/glm-5 | 28 | 28/28 (100.0%) | 0.00522 | 0.00348 | 28 | 8,517 | 626 | 3.6 |
| cf2 | openrouter:z-ai/glm-5-turbo | 28 | 28/28 (100.0%) | 0.00704 | 0.00547 | 28 | 7,861 | 421 | 3.7 |
| cf2 | openrouter:z-ai/glm-5.2#off | 28 | 28/28 (100.0%) | 0.00309 | 0.00252 | 28 | 8,509 | 401 | 3.8 |
| cf2 | openrouter:z-ai/glm-5.3 | 28 | 28/28 (100.0%) | 0.00106 | 0.00068 | 28 | 6,812 | 379 | 3.1 |
| cf2 | openrouter:z-ai/glm-5.3-flashx | 28 | 28/28 (100.0%) | 0.00225 | 0.00172 | 28 | 8,823 | 792 | 4.0 |
| cf2 | openrouter:anthropic/claude-haiku-5.5 | 280 | 279/280 (99.6%) | 0.00099 | 0.00069 | 280 | 9,287 | 818 | 3.2 |
| cf2 | openrouter:deepseek/deepseek-v4-flash | 280 | 278/280 (99.3%) | 0.00067 | 0.00041 | 280 | 8,988 | 727 | 3.6 |
| cf2 | openrouter:liquid/lfm-2.5-24b-a2b | 84 | 83/84 (98.8%) | 0.00176 | 0.00142 | 84 | 17,390 | 1,296 | 5.7 |
| cf2 | openrouter:deepseek/deepseek-v4-flash-0731 | 280 | 276/280 (98.6%) | 0.00040 | 0.00027 | 280 | 10,237 | 825 | 3.8 |
| cf2 | openrouter:inception/mercury-3 | 280 | 275/280 (98.2%) | 0.00077 | 0.00054 | 280 | 11,602 | 945 | 4.1 |
| cf2 | openrouter:inclusionai/ling-3.0-flash | 280 | 275/280 (98.2%) | 0.00018 | 0.00010 | 280 | 11,762 | 694 | 3.8 |
| cf2 | openrouter:deepseek/deepseek-v4-flash-0731#off | 280 | 274/280 (97.9%) | 0.00031 | 0.00021 | 280 | 9,268 | 521 | 3.5 |
| cf2 | openrouter:deepseek/deepseek-v4.1-flash#off | 84 | 82/84 (97.6%) | 0.00089 | 0.00077 | 84 | 12,148 | 680 | 4.2 |
| cf2 | openrouter:anthropic/claude-haiku-5.5#off | 280 | 272/280 (97.1%) | 0.00099 | 0.00064 | 280 | 9,787 | 634 | 3.2 |
| cf2 | openrouter:deepseek/deepseek-v4-flash#off | 280 | 271/280 (96.8%) | 0.00064 | 0.00035 | 280 | 9,944 | 533 | 3.7 |
| cf2 | openrouter:aion-labs/aion-2.0 | 28 | 27/28 (96.4%) | 0.00541 | 0.00319 | 28 | 9,361 | 947 | 3.4 |
| cf2 | openrouter:aion-labs/aion-3.0-mini | 28 | 27/28 (96.4%) | 0.00480 | 0.00284 | 28 | 9,501 | 999 | 3.5 |
| cf2 | openrouter:bytedance-seed/seed-2.0-lite | 28 | 27/28 (96.4%) | 0.00417 | 0.00303 | 28 | 10,621 | 757 | 4.5 |
| cf2 | openrouter:deepseek/deepseek-chat-v3.1 | 28 | 27/28 (96.4%) | 0.00398 | 0.00219 | 28 | 19,933 | 599 | 6.7 |
| cf2 | openrouter:deepseek/deepseek-chat-v3.1#off | 28 | 27/28 (96.4%) | 0.00288 | 0.00196 | 28 | 13,720 | 482 | 5.9 |
| cf2 | openrouter:deepseek/deepseek-v3.1-terminus#off | 28 | 27/28 (96.4%) | 0.00666 | 0.00315 | 28 | 22,324 | 628 | 7.5 |
| cf2 | openrouter:deepseek/deepseek-v3.2#off | 28 | 27/28 (96.4%) | 0.00418 | 0.00236 | 28 | 42,245 | 1,708 | 9.9 |
| cf2 | openrouter:deepseek/deepseek-v4-pro-0813#off | 28 | 27/28 (96.4%) | 0.00327 | 0.00276 | 28 | 7,214 | 397 | 3.6 |
| cf2 | openrouter:deepseek/deepseek-v4.1-flash-1017 | 28 | 27/28 (96.4%) | 0.00198 | 0.00108 | 28 | 30,643 | 1,615 | 6.4 |
| cf2 | openrouter:google/gemini-3.1-flash-lite#off | 28 | 27/28 (96.4%) | 0.00372 | 0.00253 | 28 | 12,904 | 484 | 7.1 |
| cf2 | openrouter:google/gemini-3.1-flash-lite-preview#off | 28 | 27/28 (96.4%) | 0.00413 | 0.00291 | 28 | 15,219 | 354 | 7.4 |
| cf2 | openrouter:inception/mercury-3#off | 84 | 81/84 (96.4%) | 0.00065 | 0.00047 | 84 | 11,164 | 662 | 4.1 |
| cf2 | openrouter:minimax/minimax-m2.1 | 28 | 27/28 (96.4%) | 0.00170 | 0.00158 | 28 | 5,910 | 461 | 3.1 |
| cf2 | openrouter:minimax/minimax-m2.5 | 28 | 27/28 (96.4%) | 0.00184 | 0.00128 | 28 | 9,361 | 665 | 4.1 |
| cf2 | openrouter:mistralai/mistral-large-4-0 | 28 | 27/28 (96.4%) | 0.00817 | 0.00622 | 28 | 7,876 | 576 | 3.9 |
| cf2 | openrouter:moonshotai/kimi-k2.5 | 28 | 27/28 (96.4%) | 0.00389 | 0.00275 | 28 | 6,829 | 758 | 3.5 |
| cf2 | openrouter:moonshotai/kimi-k2.7-code | 28 | 27/28 (96.4%) | 0.00395 | 0.00228 | 28 | 7,221 | 542 | 3.9 |
| cf2 | openrouter:nvidia/nemotron-3-super-120b-a12b#off | 28 | 27/28 (96.4%) | 0.00681 | 0.00342 | 28 | 17,417 | 620 | 5.8 |
| cf2 | openrouter:openai/gpt-5.6-luna-pro | 28 | 27/28 (96.4%) | 0.00514 | 0.00445 | 28 | 27,841 | 1,728 | 3.8 |
| cf2 | openrouter:poolside/laguna-s-2.1 | 28 | 27/28 (96.4%) | 0.00053 | 0.00029 | 28 | 9,465 | 739 | 3.9 |
| cf2 | openrouter:qwen/qwen-plus | 28 | 27/28 (96.4%) | 0.00202 | 0.00151 | 28 | 11,579 | 544 | 5.0 |
| cf2 | openrouter:qwen/qwen3.5-27b | 28 | 27/28 (96.4%) | 0.00391 | 0.00197 | 28 | 10,844 | 456 | 4.1 |
| cf2 | openrouter:qwen/qwen3.5-397b-a17b#off | 28 | 27/28 (96.4%) | 0.00494 | 0.00303 | 28 | 8,255 | 373 | 3.2 |
| cf2 | openrouter:qwen/qwen3.6-35b-a3b | 28 | 27/28 (96.4%) | 0.00143 | 0.00117 | 28 | 9,815 | 695 | 3.8 |
| cf2 | openrouter:qwen/qwen3.6-35b-a3b#off | 28 | 27/28 (96.4%) | 0.00119 | 0.00066 | 28 | 10,687 | 474 | 3.8 |
| cf2 | openrouter:qwen/qwen3.6-flash#off | 28 | 27/28 (96.4%) | 0.00228 | 0.00147 | 28 | 10,019 | 361 | 3.7 |
| cf2 | openrouter:qwen/qwen3.6-plus#off | 28 | 27/28 (96.4%) | 0.00384 | 0.00212 | 28 | 9,335 | 413 | 3.8 |
| cf2 | openrouter:qwen/qwen3.7-plus#off | 28 | 27/28 (96.4%) | 0.00191 | 0.00126 | 28 | 9,094 | 440 | 3.6 |
| cf2 | openrouter:qwen/qwen3.8-27b | 28 | 27/28 (96.4%) | 0.00357 | 0.00272 | 28 | 9,611 | 872 | 3.7 |
| cf2 | openrouter:qwen/qwen3.8-flash | 28 | 27/28 (96.4%) | 0.00124 | 0.00092 | 28 | 13,884 | 1,460 | 5.2 |
| cf2 | openrouter:qwen/qwen3.8-omni-flash | 28 | 27/28 (96.4%) | 0.00262 | 0.00176 | 28 | 16,848 | 1,722 | 5.6 |
| cf2 | openrouter:stepfun/step-3.7-flash | 28 | 27/28 (96.4%) | 0.00212 | 0.00155 | 28 | 10,229 | 834 | 3.9 |
| cf2 | openrouter:tencent/hy4-preview#off | 28 | 27/28 (96.4%) | 0.00408 | 0.00306 | 28 | 11,043 | 490 | 4.3 |
| cf2 | openrouter:xiaomi/mimo-v2.5-pro | 28 | 27/28 (96.4%) | 0.00123 | 0.00092 | 28 | 8,100 | 608 | 3.3 |
| cf2 | openrouter:xiaomi/mimo-v2.6-flash | 84 | 81/84 (96.4%) | 0.00090 | 0.00051 | 84 | 9,744 | 880 | 3.9 |
| cf2 | openrouter:z-ai/glm-4.5v | 28 | 27/28 (96.4%) | 0.00463 | 0.00251 | 28 | 7,359 | 476 | 3.3 |
| cf2 | openrouter:z-ai/glm-5.1 | 28 | 27/28 (96.4%) | 0.00794 | 0.00457 | 28 | 9,365 | 496 | 4.0 |
| cf2 | openrouter:z-ai/glm-5.1#off | 28 | 27/28 (96.4%) | 0.00684 | 0.00409 | 28 | 8,938 | 309 | 3.8 |
| cf2 | openrouter:z-ai/glm-5.2 | 28 | 27/28 (96.4%) | 0.00327 | 0.00269 | 28 | 7,009 | 433 | 3.5 |
| cf2 | openrouter:z-ai/glm-5.3-flash | 28 | 27/28 (96.4%) | 0.00168 | 0.00090 | 28 | 9,694 | 944 | 4.5 |
| cf2 | openrouter:z-ai/glm-5v-turbo | 28 | 27/28 (96.4%) | 0.00494 | 0.00333 | 28 | 6,704 | 456 | 3.1 |
| cf2 | openrouter:stepfun/step-3.5-flash | 280 | 269/280 (96.1%) | 0.00153 | 0.00091 | 280 | 12,349 | 993 | 4.8 |
| cf2 | openrouter:inception/mercury-2.5 | 280 | 267/280 (95.4%) | 0.00046 | 0.00035 | 280 | 9,244 | 821 | 3.9 |
| cf2 | openrouter:poolside/laguna-s-2.1#off | 280 | 267/280 (95.4%) | 0.00055 | 0.00033 | 280 | 9,481 | 522 | 3.7 |
| cf2 | openrouter:inclusionai/ling-3.1-flash#off | 84 | 80/84 (95.2%) | 0.00051 | 0.00038 | 84 | 9,892 | 557 | 3.6 |
| cf2 | openrouter:qwen/qwen3.5-flash-02-23 | 84 | 80/84 (95.2%) | 0.00110 | 0.00063 | 84 | 13,629 | 828 | 4.8 |
| cf2 | openrouter:deepseek/deepseek-v4.1-flash | 280 | 265/280 (94.6%) | 0.00164 | 0.00112 | 280 | 19,217 | 1,290 | 5.2 |
| cf2 | openrouter:inclusionai/ling-3.1-flash | 84 | 79/84 (94.0%) | 0.00060 | 0.00045 | 84 | 9,829 | 1,022 | 3.7 |
| cf2 | openrouter:cohere/command-a-plus | 28 | 26/28 (92.9%) | 0.00731 | 0.00313 | 28 | 17,312 | 1,408 | 6.9 |
| cf2 | openrouter:deepseek/deepseek-v3.1-terminus | 28 | 26/28 (92.9%) | 0.00462 | 0.00275 | 28 | 15,123 | 539 | 5.9 |
| cf2 | openrouter:deepseek/deepseek-v3.2 | 28 | 26/28 (92.9%) | 0.00363 | 0.00220 | 28 | 31,025 | 1,536 | 8.9 |
| cf2 | openrouter:deepseek/deepseek-v4-flash-vision-exp | 28 | 26/28 (92.9%) | 0.00145 | 0.00101 | 28 | 9,696 | 821 | 3.8 |
| cf2 | openrouter:elorian/glimpse#off | 28 | 26/28 (92.9%) | 0.00588 | 0.00452 | 28 | 14,195 | 531 | 5.1 |
| cf2 | openrouter:google/gemini-3-flash-preview | 28 | 26/28 (92.9%) | 0.00581 | 0.00302 | 28 | 9,589 | 383 | 5.3 |
| cf2 | openrouter:google/gemini-3-flash-preview#off | 28 | 26/28 (92.9%) | 0.00614 | 0.00329 | 28 | 10,160 | 397 | 5.6 |
| cf2 | openrouter:google/gemini-3.1-flash-lite | 28 | 26/28 (92.9%) | 0.00382 | 0.00233 | 28 | 13,947 | 382 | 7.4 |
| cf2 | openrouter:google/gemini-3.7-flash | 28 | 26/28 (92.9%) | 0.00878 | 0.00598 | 28 | 9,494 | 443 | 5.4 |
| cf2 | openrouter:meta/muse-spark-1.2 | 28 | 26/28 (92.9%) | 0.01338 | 0.00857 | 28 | 16,382 | 1,513 | 5.2 |
| cf2 | openrouter:minimax/minimax-m2 | 28 | 26/28 (92.9%) | 0.00219 | 0.00141 | 28 | 6,839 | 435 | 3.2 |
| cf2 | openrouter:minimax/minimax-m2.7 | 28 | 26/28 (92.9%) | 0.00224 | 0.00149 | 28 | 7,838 | 484 | 3.3 |
| cf2 | openrouter:minimax/minimax-m3.1-flash | 28 | 26/28 (92.9%) | 0.00253 | 0.00131 | 28 | 23,640 | 2,007 | 6.2 |
| cf2 | openrouter:mistralai/devstral-2512 | 28 | 26/28 (92.9%) | 0.00247 | 0.00140 | 28 | 7,958 | 286 | 3.2 |
| cf2 | openrouter:moonshotai/kimi-k2.6#off | 28 | 26/28 (92.9%) | 0.00353 | 0.00200 | 28 | 8,061 | 301 | 3.9 |
| cf2 | openrouter:nvidia/nemotron-3-ultra-550b-a55b#off | 28 | 26/28 (92.9%) | 0.00381 | 0.00259 | 28 | 9,438 | 289 | 3.6 |
| cf2 | openrouter:nvidia/nemotron-3.5-lightning#off | 28 | 26/28 (92.9%) | 0.00148 | 0.00078 | 28 | 20,766 | 866 | 6.2 |
| cf2 | openrouter:openai/gpt-5-mini | 28 | 26/28 (92.9%) | 0.00462 | 0.00331 | 28 | 18,224 | 1,297 | 7.1 |
| cf2 | openrouter:openai/gpt-5.4-mini#off | 28 | 26/28 (92.9%) | 0.00605 | 0.00382 | 28 | 9,974 | 398 | 4.3 |
| cf2 | openrouter:openai/gpt-5.6-luna | 28 | 26/28 (92.9%) | 0.00136 | 0.00102 | 28 | 7,721 | 391 | 4.1 |
| cf2 | openrouter:openai/gpt-6-luna | 28 | 26/28 (92.9%) | 0.00069 | 0.00054 | 28 | 8,877 | 414 | 5.1 |
| cf2 | openrouter:poolside/laguna-xs-2.1 | 84 | 78/84 (92.9%) | 0.00080 | 0.00032 | 84 | 14,851 | 461 | 5.1 |
| cf2 | openrouter:poolside/laguna-xs-2.1#off | 28 | 26/28 (92.9%) | 0.00067 | 0.00037 | 28 | 13,244 | 377 | 4.9 |
| cf2 | openrouter:prism-ml/ternary-bonsai-2-27b | 84 | 78/84 (92.9%) | 0.00118 | 0.00073 | 84 | 9,894 | 1,234 | 4.1 |
| cf2 | openrouter:qwen/qwen3.5-122b-a10b | 28 | 26/28 (92.9%) | 0.00551 | 0.00314 | 28 | 10,362 | 427 | 3.7 |
| cf2 | openrouter:qwen/qwen3.5-35b-a3b#off | 28 | 26/28 (92.9%) | 0.00265 | 0.00117 | 28 | 17,004 | 540 | 4.8 |
| cf2 | openrouter:qwen/qwen3.5-9b | 28 | 26/28 (92.9%) | 0.00380 | 0.00116 | 28 | 20,535 | 1,247 | 5.8 |
| cf2 | openrouter:qwen/qwen3.5-9b#off | 28 | 26/28 (92.9%) | 0.00451 | 0.00147 | 28 | 25,774 | 522 | 5.9 |
| cf2 | openrouter:qwen/qwen3.6-plus | 28 | 26/28 (92.9%) | 0.00307 | 0.00239 | 28 | 6,354 | 514 | 3.2 |
| cf2 | openrouter:qwen/qwen3.7-max#off | 28 | 26/28 (92.9%) | 0.00762 | 0.00498 | 28 | 7,790 | 309 | 3.7 |
| cf2 | openrouter:qwen/qwen3.8-27b#off | 28 | 26/28 (92.9%) | 0.00210 | 0.00164 | 28 | 7,698 | 381 | 3.4 |
| cf2 | openrouter:qwen/qwen3.8-flash#off | 28 | 26/28 (92.9%) | 0.00121 | 0.00049 | 28 | 23,561 | 530 | 6.0 |
| cf2 | openrouter:qwen/qwen3.8-omni-flash#off | 28 | 26/28 (92.9%) | 0.00202 | 0.00112 | 28 | 18,334 | 640 | 4.9 |
| cf2 | openrouter:stepfun/step-5-preview | 28 | 26/28 (92.9%) | 0.00747 | 0.00531 | 28 | 13,156 | 1,361 | 4.8 |
| cf2 | openrouter:tencent/hy3 | 28 | 26/28 (92.9%) | 0.00078 | 0.00070 | 28 | 7,504 | 503 | 3.7 |
| cf2 | openrouter:tencent/hy3#off | 28 | 26/28 (92.9%) | 0.00063 | 0.00049 | 28 | 6,818 | 369 | 3.4 |
| cf2 | openrouter:tencent/hy3-preview#off | 28 | 26/28 (92.9%) | 0.00093 | 0.00068 | 28 | 6,964 | 350 | 3.2 |
| cf2 | openrouter:thinkingmachines/inkling#off | 28 | 26/28 (92.9%) | 0.00742 | 0.00327 | 28 | 8,626 | 176 | 4.0 |
| cf2 | openrouter:thinkingmachines/inkling-small | 28 | 26/28 (92.9%) | 0.00148 | 0.00093 | 28 | 7,920 | 205 | 4.2 |
| cf2 | openrouter:upstage/solar-pro4 | 28 | 26/28 (92.9%) | 0.00104 | 0.00064 | 28 | 8,196 | 260 | 3.3 |
| cf2 | openrouter:upstage/solar-pro4#off | 28 | 26/28 (92.9%) | 0.00178 | 0.00095 | 28 | 13,467 | 320 | 4.3 |
| cf2 | openrouter:x-ai/grok-4.20 | 28 | 26/28 (92.9%) | 0.01639 | 0.00647 | 28 | 35,351 | 383 | 8.8 |
| cf2 | openrouter:xiaomi/mimo-v2.6-flash#off | 28 | 26/28 (92.9%) | 0.00175 | 0.00054 | 28 | 16,317 | 1,302 | 4.3 |
| cf2 | openrouter:z-ai/glm-4.5#off | 28 | 26/28 (92.9%) | 0.00313 | 0.00258 | 28 | 7,089 | 307 | 3.5 |
| cf2 | openrouter:z-ai/glm-4.6 | 28 | 26/28 (92.9%) | 0.00371 | 0.00241 | 28 | 16,503 | 417 | 6.2 |
| cf2 | openrouter:z-ai/glm-4.7 | 28 | 26/28 (92.9%) | 0.00316 | 0.00231 | 28 | 8,435 | 640 | 4.0 |
| cf2 | openrouter:z-ai/glm-4.7-flash | 84 | 78/84 (92.9%) | 0.00088 | 0.00058 | 84 | 9,700 | 732 | 4.0 |
| cf2 | openrouter:z-ai/glm-5#off | 28 | 26/28 (92.9%) | 0.00349 | 0.00222 | 28 | 7,076 | 261 | 3.4 |
| cf2 | openrouter:z-ai/glm-5-turbo#off | 28 | 26/28 (92.9%) | 0.00684 | 0.00555 | 28 | 7,235 | 302 | 3.5 |
| cf2 | openrouter:z-ai/glm-5v-turbo#off | 28 | 26/28 (92.9%) | 0.00465 | 0.00249 | 28 | 7,981 | 309 | 3.6 |
| cf2 | openrouter:qwen/qwen3.7-flash | 84 | 77/84 (91.7%) | 0.00033 | 0.00026 | 84 | 10,302 | 740 | 4.0 |
| cf2 | openrouter:bytedance-seed/seed-2.0-mini | 84 | 76/84 (90.5%) | 0.00151 | 0.00121 | 84 | 10,583 | 1,141 | 4.5 |
| cf2 | openrouter:openai/gpt-6-luna-pro | 84 | 76/84 (90.5%) | 0.00223 | 0.00175 | 84 | 24,753 | 1,438 | 4.5 |
| cf2 | openrouter:bytedance-seed/seed-1.6 | 28 | 25/28 (89.3%) | 0.00645 | 0.00410 | 28 | 12,306 | 1,579 | 4.8 |
| cf2 | openrouter:bytedance-seed/seed-2.0-mini#off | 28 | 25/28 (89.3%) | 0.00192 | 0.00100 | 28 | 16,861 | 585 | 6.0 |
| cf2 | openrouter:deepseek/deepseek-v4-pro#off | 28 | 25/28 (89.3%) | 0.00100 | 0.00069 | 28 | 9,953 | 547 | 3.7 |
| cf2 | openrouter:deepseek/deepseek-v4.1-flash-1017#off | 28 | 25/28 (89.3%) | 0.00107 | 0.00081 | 28 | 22,886 | 678 | 5.4 |
| cf2 | openrouter:google/gemma-4-26b-a4b-it | 28 | 25/28 (89.3%) | 0.00083 | 0.00035 | 28 | 17,648 | 461 | 7.8 |
| cf2 | openrouter:google/gemma-4-31b-it#off | 28 | 25/28 (89.3%) | 0.00241 | 0.00109 | 28 | 11,443 | 310 | 5.0 |
| cf2 | openrouter:ibm-granite/granite-4.2-8b | 28 | 25/28 (89.3%) | 0.00090 | 0.00075 | 28 | 13,902 | 1,983 | 5.7 |
| cf2 | openrouter:inception/mercury-2.5#off | 28 | 25/28 (89.3%) | 0.00041 | 0.00027 | 28 | 10,581 | 348 | 4.2 |
| cf2 | openrouter:meta/muse-spark-1.1 | 28 | 25/28 (89.3%) | 0.01028 | 0.00728 | 28 | 13,070 | 987 | 4.1 |
| cf2 | openrouter:minimax/minimax-m3#off | 28 | 25/28 (89.3%) | 0.00206 | 0.00140 | 28 | 11,153 | 500 | 4.2 |
| cf2 | openrouter:mistralai/mistral-medium-3 | 28 | 25/28 (89.3%) | 0.00274 | 0.00159 | 28 | 8,740 | 298 | 3.5 |
| cf2 | openrouter:moonshotai/kimi-k2 | 28 | 25/28 (89.3%) | 0.00655 | 0.00313 | 28 | 8,834 | 455 | 3.7 |
| cf2 | openrouter:moonshotai/kimi-k2-0905 | 28 | 25/28 (89.3%) | 0.00472 | 0.00307 | 28 | 6,527 | 323 | 3.4 |
| cf2 | openrouter:nvidia/nemotron-3-nano-30b-a3b | 28 | 25/28 (89.3%) | 0.00150 | 0.00080 | 28 | 15,674 | 2,327 | 5.6 |
| cf2 | openrouter:nvidia/nemotron-3-super-120b-a12b | 28 | 25/28 (89.3%) | 0.00697 | 0.00561 | 28 | 13,170 | 1,398 | 5.9 |
| cf2 | openrouter:openai/gpt-5.4-mini | 28 | 25/28 (89.3%) | 0.00576 | 0.00363 | 28 | 10,340 | 392 | 4.4 |
| cf2 | openrouter:openai/gpt-5.4-nano#off | 28 | 25/28 (89.3%) | 0.00182 | 0.00127 | 28 | 11,401 | 384 | 5.1 |
| cf2 | openrouter:openai/gpt-5.6-luna-pro#off | 28 | 25/28 (89.3%) | 0.00400 | 0.00303 | 28 | 27,983 | 911 | 3.9 |
| cf2 | openrouter:openai/gpt-6-luna-pro#off | 28 | 25/28 (89.3%) | 0.00196 | 0.00152 | 28 | 25,701 | 538 | 4.7 |
| cf2 | openrouter:openai/gpt-oss-120b | 28 | 25/28 (89.3%) | 0.00133 | 0.00087 | 28 | 10,793 | 581 | 5.3 |
| cf2 | openrouter:qwen/qwen3-coder | 28 | 25/28 (89.3%) | 0.00324 | 0.00136 | 28 | 20,489 | 558 | 5.6 |
| cf2 | openrouter:qwen/qwen3-coder-flash | 28 | 25/28 (89.3%) | 0.00371 | 0.00278 | 28 | 27,945 | 898 | 8.5 |
| cf2 | openrouter:qwen/qwen3-coder-next | 28 | 25/28 (89.3%) | 0.00165 | 0.00083 | 28 | 15,105 | 454 | 4.7 |
| cf2 | openrouter:qwen/qwen3-next-80b-a3b-instruct | 28 | 25/28 (89.3%) | 0.00177 | 0.00080 | 28 | 13,318 | 373 | 4.8 |
| cf2 | openrouter:qwen/qwen3.5-27b#off | 28 | 25/28 (89.3%) | 0.00447 | 0.00197 | 28 | 13,369 | 396 | 4.3 |
| cf2 | openrouter:qwen/qwen3.5-flash-02-23#off | 28 | 25/28 (89.3%) | 0.00104 | 0.00043 | 28 | 13,018 | 479 | 4.5 |
| cf2 | openrouter:qwen/qwen3.5-plus-20260420#off | 28 | 25/28 (89.3%) | 0.00388 | 0.00158 | 28 | 10,503 | 406 | 4.0 |
| cf2 | openrouter:qwen/qwen3.6-27b#off | 28 | 25/28 (89.3%) | 0.00205 | 0.00172 | 28 | 7,286 | 386 | 3.2 |
| cf2 | openrouter:qwen/qwen3.6-flash | 28 | 25/28 (89.3%) | 0.00271 | 0.00212 | 28 | 10,024 | 740 | 3.8 |
| cf2 | openrouter:qwen/qwen3.7-flash#off | 28 | 25/28 (89.3%) | 0.00029 | 0.00018 | 28 | 10,856 | 380 | 4.0 |
| cf2 | openrouter:tencent/hy4-preview | 28 | 25/28 (89.3%) | 0.00691 | 0.00448 | 28 | 14,443 | 1,217 | 5.2 |
| cf2 | openrouter:thinkingmachines/inkling-small#off | 28 | 25/28 (89.3%) | 0.00110 | 0.00076 | 28 | 5,751 | 159 | 3.8 |
| cf2 | openrouter:upstage/solar-mini4#off | 28 | 25/28 (89.3%) | 0.00103 | 0.00038 | 28 | 29,872 | 582 | 5.8 |
| cf2 | openrouter:z-ai/glm-4.5-air#off | 28 | 25/28 (89.3%) | 0.00086 | 0.00044 | 28 | 12,974 | 435 | 5.2 |
| cf2 | openrouter:z-ai/glm-4.5v#off | 28 | 25/28 (89.3%) | 0.00339 | 0.00190 | 28 | 6,616 | 279 | 3.2 |
| cf2 | openrouter:z-ai/glm-4.7#off | 28 | 25/28 (89.3%) | 0.00282 | 0.00176 | 28 | 9,487 | 336 | 3.8 |
| cf2 | openrouter:deepseek/deepseek-v3.2-exp#off | 26 | 23/26 (88.5%) | 0.01701 | 0.00714 | 26 | 59,642 | 1,705 | 12.0 |
| cf2 | openrouter:google/gemma-4-31b-it | 28 | 24/28 (85.7%) | 0.00241 | 0.00103 | 28 | 11,411 | 316 | 5.0 |
| cf2 | openrouter:inclusionai/ling-3.0-flash#off | 28 | 24/28 (85.7%) | 0.00016 | 0.00008 | 28 | 13,501 | 478 | 4.0 |
| cf2 | openrouter:nvidia/nemotron-3.5-lightning | 28 | 24/28 (85.7%) | 0.00179 | 0.00091 | 28 | 25,120 | 1,577 | 6.6 |
| cf2 | openrouter:thinkingmachines/inkling | 28 | 24/28 (85.7%) | 0.00763 | 0.00330 | 28 | 10,660 | 251 | 4.0 |
| cf2 | openrouter:upstage/solar-mini4 | 28 | 24/28 (85.7%) | 0.00071 | 0.00032 | 28 | 16,372 | 532 | 4.8 |
| cf2 | openrouter:z-ai/glm-4.7-flash#off | 28 | 24/28 (85.7%) | 0.00076 | 0.00032 | 28 | 10,254 | 341 | 4.1 |
| cf2 | openrouter:openai/gpt-5.6-luna#off | 27 | 23/27 (85.2%) | 0.00131 | 0.00085 | 27 | 8,137 | 455 | 4.1 |
| cf2 | openrouter:google/gemma-4-26b-a4b-it#off | 28 | 23/28 (82.1%) | 0.00069 | 0.00032 | 28 | 13,357 | 542 | 6.6 |
| cf2 | openrouter:ibm-granite/granite-4.2-8b#off | 28 | 23/28 (82.1%) | 0.00104 | 0.00035 | 28 | 29,748 | 1,153 | 6.8 |
| cf2 | openrouter:inception/mercury-2 | 28 | 23/28 (82.1%) | 0.00270 | 0.00133 | 28 | 13,112 | 636 | 5.9 |
| cf2 | openrouter:openai/gpt-5-nano | 28 | 23/28 (82.1%) | 0.00146 | 0.00116 | 28 | 20,571 | 2,430 | 8.0 |
| cf2 | openrouter:openai/gpt-6-luna#off | 28 | 23/28 (82.1%) | 0.00070 | 0.00052 | 28 | 10,951 | 277 | 5.2 |
| cf2 | openrouter:openai/gpt-oss-20b | 28 | 23/28 (82.1%) | 0.00027 | 0.00013 | 28 | 16,470 | 765 | 7.1 |
| cf2 | openrouter:qwen/qwen3-235b-a22b-2507 | 28 | 23/28 (82.1%) | 0.00118 | 0.00058 | 28 | 11,406 | 285 | 4.6 |
| cf2 | openrouter:bytedance-seed/seed-2.0-lite#off | 19 | 15/19 (78.9%) | 0.00419 | 0.00179 | 19 | 13,667 | 387 | 4.4 |
| cf2 | openrouter:mistralai/mixtral-8x22b-instruct | 19 | 15/19 (78.9%) | 0.00911 | 0.00454 | 19 | 7,336 | 449 | 3.4 |
| cf2 | openrouter:openai/gpt-5.4-nano | 19 | 15/19 (78.9%) | 0.00168 | 0.00119 | 19 | 8,749 | 377 | 3.7 |
| cf2 | openrouter:qwen/qwen3-vl-235b-a22b-instruct | 19 | 15/19 (78.9%) | 0.00195 | 0.00098 | 19 | 10,304 | 281 | 4.2 |
| cf2 | openrouter:z-ai/glm-4.5-air | 19 | 15/19 (78.9%) | 0.00114 | 0.00071 | 19 | 13,848 | 714 | 5.5 |
| cf2 | openrouter:z-ai/glm-4.6#off | 19 | 15/19 (78.9%) | 0.00317 | 0.00161 | 19 | 13,254 | 342 | 5.6 |
| cf2 | openrouter:qwen/qwen3-coder-30b-a3b-instruct | 28 | 22/28 (78.6%) | 0.00192 | 0.00121 | 28 | 24,536 | 739 | 7.5 |
| cf2 | openrouter:mistralai/mistral-medium-3.1 | 18 | 14/18 (77.8%) | 0.00292 | 0.00147 | 18 | 10,910 | 318 | 3.9 |
| cf2 | openrouter:nex-agi/nex-n2.5-pro#off | 28 | 21/28 (75.0%) | 0.00031 | 0.00018 | 28 | 9,358 | 399 | 4.0 |
| cf2 | openrouter:mistralai/ministral-8b-2512 | 18 | 13/18 (72.2%) | 0.00122 | 0.00031 | 18 | 14,677 | 460 | 5.0 |
| cf2 | openrouter:mistralai/mistral-small-2603 | 18 | 13/18 (72.2%) | 0.00092 | 0.00039 | 18 | 12,786 | 371 | 4.6 |
| cf2 | openrouter:mistralai/mistral-small-2603#off | 14 | 10/14 (71.4%) | 0.00073 | 0.00039 | 14 | 11,127 | 338 | 4.8 |
| cf2 | openrouter:qwen/qwen3-30b-a3b-instruct-2507 | 28 | 20/28 (71.4%) | 0.00228 | 0.00078 | 28 | 22,109 | 424 | 6.5 |
| cf2 | openrouter:google/gemini-3.1-flash-lite-preview | 17 | 12/17 (70.6%) | 0.00423 | 0.00228 | 17 | 18,274 | 366 | 6.8 |
| cf2 | openrouter:qwen/qwen-2.5-72b-instruct | 17 | 12/17 (70.6%) | 0.00232 | 0.00178 | 17 | 5,857 | 531 | 2.6 |
| cf2 | openrouter:openai/gpt-5.1-codex-mini | 13 | 9/13 (69.2%) | 0.00350 | 0.00226 | 13 | 16,421 | 1,027 | 7.7 |
| cf2 | openrouter:openai/gpt-oss-safeguard-20b | 28 | 19/28 (67.9%) | 0.00066 | 0.00052 | 28 | 8,533 | 630 | 5.1 |
| cf2 | openrouter:google/gemini-2.5-flash#off | 12 | 8/12 (66.7%) | 0.00280 | 0.00208 | 12 | 9,295 | 423 | 4.2 |
| cf2 | openrouter:qwen/qwen3-vl-30b-a3b-instruct | 12 | 8/12 (66.7%) | 0.00279 | 0.00088 | 12 | 16,146 | 616 | 5.5 |
| cf2 | openrouter:deepseek/deepseek-chat | 17 | 11/17 (64.7%) | 0.00211 | 0.00124 | 17 | 6,090 | 523 | 2.7 |
| cf2 | openrouter:deepseek/deepseek-chat-v3-0324 | 17 | 11/17 (64.7%) | 0.00196 | 0.00130 | 17 | 6,286 | 242 | 3.1 |
| cf2 | openrouter:google/gemini-2.5-flash | 17 | 11/17 (64.7%) | 0.00294 | 0.00175 | 17 | 11,401 | 415 | 4.5 |
| cf2 | openrouter:mistralai/ministral-14b-2512 | 17 | 11/17 (64.7%) | 0.00115 | 0.00037 | 17 | 13,825 | 410 | 4.5 |
| cf2 | openrouter:mistralai/mistral-saba | 17 | 11/17 (64.7%) | 0.00088 | 0.00039 | 17 | 8,090 | 229 | 3.6 |
| cf2 | openrouter:openai/gpt-4.1-mini | 14 | 9/14 (64.3%) | 0.00465 | 0.00151 | 14 | 19,187 | 575 | 5.6 |
| cf2 | openrouter:bytedance-seed/seed-1.6#off | 16 | 10/16 (62.5%) | 0.00267 | 0.00170 | 16 | 7,577 | 389 | 3.0 |
| cf2 | openrouter:nvidia/nemotron-3-nano-30b-a3b#off | 28 | 17/28 (60.7%) | 0.00226 | 0.00087 | 28 | 32,738 | 761 | 9.0 |
| cf2 | openrouter:nex-agi/nex-n2.5-pro | 25 | 14/25 (56.0%) | 0.00032 | 0.00026 | 25 | 6,273 | 439 | 3.5 |
| cf2 | openrouter:minimax/minimax-m1#off | 9 | 5/9 (55.6%) | 0.00875 | 0.00524 | 9 | 12,819 | 772 | 5.0 |
| cf2 | openrouter:upstage/solar-pro-3 | 11 | 6/11 (54.5%) | 0.00501 | 0.00188 | 11 | 68,494 | 1,259 | 14.7 |
| cf6 | openrouter:deepseek/deepseek-v4-flash-0731#off | 480 | 479/480 (99.8%) | 0.00285 | 0.00187 | 480 | 20,773 | 724 | 4.6 |
| cf6 | openrouter:anthropic/claude-haiku-5.5 | 480 | 476/480 (99.2%) | 0.00144 | 0.00107 | 480 | 18,557 | 1,003 | 3.4 |
| cf6 | openrouter:inclusionai/ling-3.0-flash | 479 | 470/479 (98.1%) | 0.00025 | 0.00015 | 479 | 18,592 | 842 | 4.0 |

## Hard tier (cf3a, cf3b), per store and model

### hard

| store | model | runs | pass rate | mean list $/run | median list $/run | priced runs | mean prompt tok | mean output tok | mean steps |
|---|---|---|---|---|---|---|---|---|---|
| cf3a | openrouter:openai/gpt-6-luna-pro | 42 | 42/42 (100.0%) | 0.00391 | 0.00347 | 42 | 46,420 | 2,769 | 7.0 |
| cf3a | openrouter:qwen/qwen3.7-flash | 42 | 42/42 (100.0%) | 0.00062 | 0.00039 | 42 | 17,499 | 1,359 | 5.5 |
| cf3a | openrouter:anthropic/claude-haiku-5.5 | 140 | 139/140 (99.3%) | 0.00154 | 0.00118 | 140 | 15,945 | 1,392 | 3.9 |
| cf3a | openrouter:anthropic/claude-haiku-5.5#off | 140 | 139/140 (99.3%) | 0.00130 | 0.00107 | 140 | 16,351 | 1,083 | 3.9 |
| cf3a | openrouter:deepseek/deepseek-v4-flash-0731#off | 140 | 139/140 (99.3%) | 0.00068 | 0.00045 | 140 | 14,055 | 951 | 4.7 |
| cf3a | openrouter:inclusionai/ling-3.0-flash | 140 | 139/140 (99.3%) | 0.00031 | 0.00019 | 140 | 19,876 | 1,471 | 5.5 |
| cf3a | openrouter:deepseek/deepseek-v4.1-flash | 140 | 138/140 (98.6%) | 0.00239 | 0.00151 | 140 | 21,563 | 1,929 | 5.9 |
| cf3a | openrouter:poolside/laguna-s-2.1#off | 140 | 138/140 (98.6%) | 0.00112 | 0.00059 | 140 | 19,568 | 1,118 | 5.9 |
| cf3a | openrouter:bytedance-seed/seed-2.0-mini | 42 | 41/42 (97.6%) | 0.00345 | 0.00234 | 42 | 23,698 | 2,227 | 8.0 |
| cf3a | openrouter:deepseek/deepseek-v4.1-flash#off | 42 | 41/42 (97.6%) | 0.00141 | 0.00125 | 42 | 17,899 | 1,059 | 5.3 |
| cf3a | openrouter:inclusionai/ling-3.1-flash#off | 42 | 41/42 (97.6%) | 0.00103 | 0.00053 | 42 | 20,151 | 1,096 | 5.2 |
| cf3a | openrouter:xiaomi/mimo-v2.6-flash | 42 | 41/42 (97.6%) | 0.00170 | 0.00076 | 42 | 14,640 | 1,394 | 4.6 |
| cf3a | openrouter:deepseek/deepseek-v4-flash | 140 | 136/140 (97.1%) | 0.00132 | 0.00076 | 140 | 18,659 | 1,619 | 5.6 |
| cf3a | openrouter:deepseek/deepseek-v4-flash#off | 140 | 136/140 (97.1%) | 0.00113 | 0.00067 | 140 | 19,285 | 1,061 | 5.5 |
| cf3a | openrouter:deepseek/deepseek-v4-flash-0731 | 140 | 136/140 (97.1%) | 0.00086 | 0.00057 | 140 | 16,259 | 1,551 | 5.0 |
| cf3a | openrouter:inception/mercury-3 | 140 | 136/140 (97.1%) | 0.00137 | 0.00091 | 140 | 23,103 | 1,834 | 5.6 |
| cf3a | openrouter:stepfun/step-3.5-flash | 140 | 134/140 (95.7%) | 0.00299 | 0.00172 | 140 | 23,451 | 2,087 | 7.4 |
| cf3a | openrouter:inception/mercury-3#off | 42 | 40/42 (95.2%) | 0.00140 | 0.00081 | 42 | 22,691 | 1,385 | 6.0 |
| cf3a | openrouter:inclusionai/ling-3.1-flash | 42 | 40/42 (95.2%) | 0.00092 | 0.00071 | 42 | 13,406 | 1,612 | 4.5 |
| cf3a | openrouter:poolside/laguna-xs-2.1 | 42 | 40/42 (95.2%) | 0.00125 | 0.00077 | 42 | 27,855 | 967 | 9.0 |
| cf3a | openrouter:inception/mercury-2.5 | 140 | 128/140 (91.4%) | 0.00087 | 0.00054 | 140 | 20,097 | 1,218 | 6.7 |
| cf3a | openrouter:liquid/lfm-2.5-24b-a2b | 42 | 38/42 (90.5%) | 0.00312 | 0.00254 | 42 | 32,989 | 2,285 | 8.1 |
| cf3a | openrouter:qwen/qwen3.5-flash-02-23 | 42 | 38/42 (90.5%) | 0.00211 | 0.00150 | 42 | 26,131 | 1,359 | 8.3 |
| cf3a | openrouter:prism-ml/ternary-bonsai-2-27b | 42 | 37/42 (88.1%) | 0.00197 | 0.00149 | 42 | 13,224 | 2,117 | 5.4 |
| cf3a | openrouter:z-ai/glm-4.7-flash | 42 | 37/42 (88.1%) | 0.00196 | 0.00108 | 42 | 22,626 | 1,387 | 6.7 |
| cf3b | openrouter:anthropic/claude-opus-5.5 | 42 | 42/42 (100.0%) | 0.04582 | 0.03845 | 42 | 13,867 | 1,040 | 3.7 |
| cf3b | openrouter:anthropic/claude-sonnet-5.5 | 42 | 42/42 (100.0%) | 0.02286 | 0.02000 | 42 | 14,317 | 972 | 3.5 |
| cf3b | openrouter:google/gemini-4-argon | 42 | 42/42 (100.0%) | 0.03488 | 0.02357 | 42 | 14,685 | 745 | 4.7 |
| cf3b | openrouter:moonshotai/kimi-k3.1-pro | 42 | 42/42 (100.0%) | 0.02874 | 0.02311 | 42 | 23,717 | 1,553 | 7.9 |
| cf3b | openrouter:openai/gpt-5.6-sol | 42 | 42/42 (100.0%) | 0.03965 | 0.03226 | 42 | 17,061 | 783 | 7.5 |

## Frontier and standard models (Opus, Sonnet, gemini-4-argon, Haiku), every store

### frontier

| store | model | runs | pass rate | mean list $/run | median list $/run | priced runs | mean prompt tok | mean output tok | mean steps |
|---|---|---|---|---|---|---|---|---|---|
| bank1 | google-gemini:gemini-4-argon | 102 | 102/102 (100.0%) | 0.02066 | 0.01505 | 102 | 8,181 | 514 | 3.6 |
| cf1 | openrouter:anthropic/claude-haiku-4.5 | 6 | 6/6 (100.0%) | 0.01880 | 0.02067 | 6 | 15,641 | 775 | 5.3 |
| cf1 | openrouter:anthropic/claude-haiku-4.5#off | 6 | 6/6 (100.0%) | 0.01657 | 0.01810 | 6 | 13,606 | 681 | 4.8 |
| cf1 | openrouter:anthropic/claude-haiku-5.5 | 60 | 60/60 (100.0%) | 0.00088 | 0.00094 | 60 | 9,048 | 807 | 3.1 |
| cf1 | openrouter:anthropic/claude-haiku-5.5#off | 60 | 60/60 (100.0%) | 0.00088 | 0.00083 | 60 | 10,697 | 739 | 3.6 |
| cf1 | openrouter:anthropic/claude-opus-4.1 | 6 | 6/6 (100.0%) | 0.14105 | 0.15434 | 6 | 16,396 | 821 | 6.2 |
| cf1 | openrouter:anthropic/claude-opus-4.1#off | 6 | 6/6 (100.0%) | 0.15756 | 0.16119 | 6 | 17,281 | 889 | 6.3 |
| cf1 | openrouter:anthropic/claude-opus-4.5 | 6 | 6/6 (100.0%) | 0.05874 | 0.06056 | 6 | 9,261 | 497 | 3.5 |
| cf1 | openrouter:anthropic/claude-opus-4.5#off | 6 | 6/6 (100.0%) | 0.07035 | 0.06324 | 6 | 11,252 | 564 | 4.2 |
| cf1 | openrouter:anthropic/claude-opus-4.6 | 6 | 6/6 (100.0%) | 0.07166 | 0.06651 | 6 | 10,953 | 676 | 4.2 |
| cf1 | openrouter:anthropic/claude-opus-4.6#off | 6 | 6/6 (100.0%) | 0.07161 | 0.07324 | 6 | 11,063 | 652 | 4.2 |
| cf1 | openrouter:anthropic/claude-opus-4.7 | 6 | 6/6 (100.0%) | 0.04327 | 0.04423 | 6 | 14,017 | 615 | 4.2 |
| cf1 | openrouter:anthropic/claude-opus-4.7#off | 6 | 6/6 (100.0%) | 0.04589 | 0.04679 | 6 | 16,146 | 672 | 4.8 |
| cf1 | openrouter:anthropic/claude-opus-4.8 | 6 | 6/6 (100.0%) | 0.04012 | 0.04220 | 6 | 11,384 | 622 | 4.0 |
| cf1 | openrouter:anthropic/claude-opus-4.8#off | 6 | 6/6 (100.0%) | 0.04058 | 0.04153 | 6 | 11,048 | 652 | 3.8 |
| cf1 | openrouter:anthropic/claude-opus-5 | 6 | 6/6 (100.0%) | 0.05498 | 0.05483 | 6 | 15,854 | 1,031 | 5.2 |
| cf1 | openrouter:anthropic/claude-opus-5#off | 6 | 6/6 (100.0%) | 0.06509 | 0.06483 | 6 | 17,347 | 1,328 | 5.3 |
| cf1 | openrouter:anthropic/claude-opus-5.5 | 6 | 6/6 (100.0%) | 0.03217 | 0.03133 | 6 | 8,915 | 696 | 3.2 |
| cf1 | openrouter:anthropic/claude-sonnet-4.5 | 6 | 6/6 (100.0%) | 0.02989 | 0.03321 | 6 | 19,462 | 798 | 6.7 |
| cf1 | openrouter:anthropic/claude-sonnet-4.5#off | 6 | 6/6 (100.0%) | 0.03055 | 0.03252 | 6 | 19,656 | 837 | 6.7 |
| cf1 | openrouter:anthropic/claude-sonnet-4.6 | 6 | 6/6 (100.0%) | 0.02288 | 0.02358 | 6 | 10,827 | 601 | 3.8 |
| cf1 | openrouter:anthropic/claude-sonnet-4.6#off | 6 | 6/6 (100.0%) | 0.02250 | 0.02275 | 6 | 10,708 | 592 | 3.8 |
| cf1 | openrouter:anthropic/claude-sonnet-5 | 6 | 6/6 (100.0%) | 0.01693 | 0.01674 | 6 | 11,950 | 658 | 4.0 |
| cf1 | openrouter:anthropic/claude-sonnet-5#off | 6 | 6/6 (100.0%) | 0.01760 | 0.01852 | 6 | 12,412 | 690 | 4.2 |
| cf1 | openrouter:anthropic/claude-sonnet-5.5 | 6 | 6/6 (100.0%) | 0.01558 | 0.01581 | 6 | 10,296 | 655 | 3.7 |
| cf1 | openrouter:google/gemini-4-argon | 6 | 6/6 (100.0%) | 0.01810 | 0.01817 | 6 | 7,454 | 339 | 3.8 |
| cf2 | openrouter:anthropic/claude-haiku-5.5 | 280 | 279/280 (99.6%) | 0.00099 | 0.00069 | 280 | 9,287 | 818 | 3.2 |
| cf2 | openrouter:anthropic/claude-haiku-5.5#off | 280 | 272/280 (97.1%) | 0.00099 | 0.00064 | 280 | 9,787 | 634 | 3.2 |
| cf3a | openrouter:anthropic/claude-haiku-5.5 | 140 | 139/140 (99.3%) | 0.00154 | 0.00118 | 140 | 15,945 | 1,392 | 3.9 |
| cf3a | openrouter:anthropic/claude-haiku-5.5#off | 140 | 139/140 (99.3%) | 0.00130 | 0.00107 | 140 | 16,351 | 1,083 | 3.9 |
| cf3b | openrouter:anthropic/claude-opus-5.5 | 42 | 42/42 (100.0%) | 0.04582 | 0.03845 | 42 | 13,867 | 1,040 | 3.7 |
| cf3b | openrouter:anthropic/claude-sonnet-5.5 | 42 | 42/42 (100.0%) | 0.02286 | 0.02000 | 42 | 14,317 | 972 | 3.5 |
| cf3b | openrouter:google/gemini-4-argon | 42 | 42/42 (100.0%) | 0.03488 | 0.02357 | 42 | 14,685 | 745 | 4.7 |
| cf5 | google-gemini:gemini-4-argon | 21 | 21/21 (100.0%) | 0.01885 | 0.01268 | 21 | 7,064 | 494 | 3.2 |
| cf6 | openrouter:anthropic/claude-haiku-5.5 | 480 | 476/480 (99.2%) | 0.00144 | 0.00107 | 480 | 18,557 | 1,003 | 3.4 |

## Pooled bank + hard tier (cf2+cf6+bank1+cf3a+cf3b), selected models

### pooled

| store | model | runs | pass rate | mean list $/run | median list $/run | priced runs | mean prompt tok | mean output tok | mean steps |
|---|---|---|---|---|---|---|---|---|---|
| bank+hard | google-gemini:gemini-4-argon | 102 | 102/102 (100.0%) | 0.02066 | 0.01505 | 102 | 8,181 | 514 | 3.6 |
| bank+hard | openrouter:anthropic/claude-opus-5.5 | 42 | 42/42 (100.0%) | 0.04582 | 0.03845 | 42 | 13,867 | 1,040 | 3.7 |
| bank+hard | openrouter:anthropic/claude-sonnet-5.5 | 42 | 42/42 (100.0%) | 0.02286 | 0.02000 | 42 | 14,317 | 972 | 3.5 |
| bank+hard | openrouter:google/gemini-4-argon | 42 | 42/42 (100.0%) | 0.03488 | 0.02357 | 42 | 14,685 | 745 | 4.7 |
| bank+hard | openrouter:anthropic/claude-haiku-5.5 | 900 | 894/900 (99.3%) | 0.00132 | 0.00096 | 900 | 15,267 | 1,006 | 3.4 |
| bank+hard | openrouter:deepseek/deepseek-v4-flash-0731#off | 900 | 892/900 (99.1%) | 0.00172 | 0.00065 | 900 | 16,149 | 696 | 4.3 |
| bank+hard | openrouter:inclusionai/ling-3.0-flash | 899 | 884/899 (98.3%) | 0.00024 | 0.00014 | 899 | 16,665 | 894 | 4.1 |
| bank+hard | openrouter:deepseek/deepseek-v4-flash-0731 | 420 | 412/420 (98.1%) | 0.00055 | 0.00037 | 420 | 12,245 | 1,067 | 4.2 |
| bank+hard | openrouter:anthropic/claude-haiku-5.5#off | 420 | 411/420 (97.9%) | 0.00109 | 0.00077 | 420 | 11,975 | 784 | 3.4 |
| bank+hard | openrouter:inception/mercury-2.5 | 420 | 395/420 (94.0%) | 0.00060 | 0.00040 | 420 | 12,862 | 953 | 4.9 |
| bank+hard | openrouter:google/gemma-4-26b-a4b-it | 28 | 25/28 (89.3%) | 0.00083 | 0.00035 | 28 | 17,648 | 461 | 7.8 |
| bank+hard | openrouter:inception/mercury-2.5#off | 28 | 25/28 (89.3%) | 0.00041 | 0.00027 | 28 | 10,581 | 348 | 4.2 |
| bank+hard | lmstudio:google/gemma-4-26b-a4b-qat | 102 | 91/102 (89.2%) | – | – | 0 | 11,942 | 1,190 | 5.6 |
| bank+hard | openrouter:inclusionai/ling-3.0-flash#off | 28 | 24/28 (85.7%) | 0.00016 | 0.00008 | 28 | 13,501 | 478 | 4.0 |
| bank+hard | openrouter:google/gemma-4-26b-a4b-it#off | 28 | 23/28 (82.1%) | 0.00069 | 0.00032 | 28 | 13,357 | 542 | 6.6 |

---

# Judge calibration recomputed from judgments.jsonl (python3 -I)

Verdict ≤ 1 = the judge flags the run as failed. Per run, the last judgment with a verdict for each (path, judge) counts (as in TriggerSim.signals). Recall = flagged gold failures / gold failures the judge gave a verdict on. Precision = gold failures among flagged. False alarms = flagged gold passes / gold passes judged. Kappa = Cohen's kappa of (verdict ≥ 2) against gold pass. Cost = mean `listPrice` over all of that judge's judgment entries (verdict or not); local judges have none.

## bank1, real runs only: 612 runs, 42 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 196 | 0 | 57% (8/14) | 24% (8/33) | 14% (25/182) | 0.27 | – | 197 |
| grader | gemini-3.8-flash | 204 | 0 | 36% (5/14) | 56% (5/9) | 2% (4/190) | 0.40 | $0.00232 | 204 |
| grader | gemini-4-argon | 204 | 0 | 36% (5/14) | 71% (5/7) | 1% (2/190) | 0.45 | $0.00320 | 204 |
| grader | gemma-4-26b-a4b-qat | 155 | 3 | 29% (4/14) | 57% (4/7) | 2% (3/141) | 0.34 | – | 178 |
| parent | qwen3.5-9b | 192 | 4 | 31% (4/13) | 40% (4/10) | 3% (6/179) | 0.31 | – | 211 |
| parent | gemini-3.8-flash | 203 | 1 | 57% (8/14) | 100% (8/8) | 0% (0/189) | 0.71 | $0.00964 | 243 |
| parent | gemini-4-argon | 204 | 0 | 71% (10/14) | 100% (10/10) | 0% (0/190) | 0.82 | $0.01461 | 207 |
| parent | gemma-4-26b-a4b-qat | 125 | 33 | 20% (2/10) | 67% (2/3) | 1% (1/115) | 0.28 | – | 216 |

## bank1, real + degraded copies: 1071 runs, 501 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 367 | 0 | 50% (92/185) | 79% (92/117) | 14% (25/182) | 0.36 | – | 369 |
| grader | gemini-3.8-flash | 663 | 0 | 44% (209/473) | 98% (209/213) | 2% (4/190) | 0.30 | $0.00263 | 663 |
| grader | gemini-4-argon | 663 | 0 | 43% (203/473) | 99% (203/205) | 1% (2/190) | 0.29 | $0.00322 | 663 |
| grader | gemma-4-26b-a4b-qat | 298 | 3 | 40% (63/157) | 95% (63/66) | 2% (3/141) | 0.37 | – | 342 |
| parent | qwen3.5-9b | 350 | 17 | 43% (73/171) | 92% (73/79) | 3% (6/179) | 0.40 | – | 420 |
| parent | gemini-3.8-flash | 657 | 6 | 55% (256/468) | 100% (256/256) | 0% (0/189) | 0.41 | $0.01006 | 796 |
| parent | gemini-4-argon | 660 | 3 | 56% (262/470) | 100% (262/262) | 0% (0/190) | 0.42 | $0.01525 | 675 |
| parent | gemma-4-26b-a4b-qat | 245 | 56 | 46% (60/130) | 98% (60/61) | 1% (1/115) | 0.44 | – | 416 |

## cf5, real runs only: 123 runs, 9 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 123 | 0 | 56% (5/9) | 31% (5/16) | 10% (11/114) | 0.34 | – | 124 |
| grader | gemini-3.8-flash | 123 | 0 | 22% (2/9) | 67% (2/3) | 1% (1/114) | 0.31 | $0.00212 | 123 |
| grader | gemini-4-argon | 123 | 0 | 33% (3/9) | 60% (3/5) | 2% (2/114) | 0.40 | $0.00316 | 123 |
| grader | gemma-4-26b-a4b-qat | 121 | 2 | 11% (1/9) | 50% (1/2) | 1% (1/112) | 0.16 | – | 134 |
| parent | qwen3.5-9b | 123 | 0 | 22% (2/9) | 29% (2/7) | 4% (5/114) | 0.20 | – | 131 |
| parent | gemini-3.8-flash | 123 | 0 | 44% (4/9) | 100% (4/4) | 0% (0/114) | 0.60 | $0.00922 | 140 |
| parent | gemini-4-argon | 123 | 0 | 78% (7/9) | 100% (7/7) | 0% (0/114) | 0.87 | $0.01372 | 124 |
| parent | gemma-4-26b-a4b-qat | 123 | 0 | 22% (2/9) | 67% (2/3) | 1% (1/114) | 0.31 | – | 147 |
| parent | claude-haiku-5.5 | 123 | 0 | 67% (6/9) | 75% (6/8) | 2% (2/114) | 0.68 | $0.00114 | 123 |
| parent | deepseek-v4-flash | 119 | 4 | 33% (3/9) | 100% (3/3) | 0% (0/110) | 0.48 | $0.00071 | 123 |
| parent | deepseek-v4-flash-0731 | 120 | 3 | 44% (4/9) | 100% (4/4) | 0% (0/111) | 0.60 | $0.00042 | 123 |
| parent | mercury-3 | 122 | 1 | 67% (6/9) | 100% (6/6) | 0% (0/113) | 0.79 | $0.00047 | 123 |
| parent | ling-3.0-flash | 121 | 2 | 22% (2/9) | 100% (2/2) | 0% (0/112) | 0.35 | $0.00015 | 123 |
| parent | ling-3.1-flash | 120 | 3 | 78% (7/9) | 100% (7/7) | 0% (0/111) | 0.87 | $0.00059 | 123 |
| parent | gpt-6-luna | 123 | 0 | 33% (3/9) | 43% (3/7) | 4% (4/114) | 0.33 | $0.00053 | 123 |
| parent | laguna-s-2.1 | 119 | 4 | 33% (3/9) | 100% (3/3) | 0% (0/110) | 0.48 | $0.00052 | 123 |
| parent | qwen3.7-flash | 121 | 2 | 56% (5/9) | 100% (5/5) | 0% (0/112) | 0.70 | $0.00025 | 123 |
| parent | glm-4.7-flash | 114 | 9 | 22% (2/9) | 67% (2/3) | 1% (1/105) | 0.31 | $0.00067 | 123 |

## cf5, real + degraded copies: 236 runs, 122 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 236 | 0 | 44% (54/122) | 83% (54/65) | 10% (11/114) | 0.34 | – | 238 |
| grader | gemini-3.8-flash | 236 | 0 | 38% (46/122) | 98% (46/47) | 1% (1/114) | 0.36 | $0.00237 | 236 |
| grader | gemini-4-argon | 236 | 0 | 38% (46/122) | 96% (46/48) | 2% (2/114) | 0.35 | $0.00322 | 236 |
| grader | gemma-4-26b-a4b-qat | 234 | 2 | 37% (45/122) | 98% (45/46) | 1% (1/112) | 0.35 | – | 262 |
| parent | qwen3.5-9b | 236 | 0 | 43% (52/122) | 91% (52/57) | 4% (5/114) | 0.38 | – | 268 |
| parent | gemini-3.8-flash | 236 | 0 | 47% (57/122) | 100% (57/57) | 0% (0/114) | 0.46 | $0.00904 | 268 |
| parent | gemini-4-argon | 236 | 0 | 51% (62/122) | 100% (62/62) | 0% (0/114) | 0.50 | $0.01391 | 241 |
| parent | gemma-4-26b-a4b-qat | 236 | 0 | 45% (55/122) | 98% (55/56) | 1% (1/114) | 0.43 | – | 291 |
| parent | claude-haiku-5.5 | 236 | 0 | 49% (60/122) | 97% (60/62) | 2% (2/114) | 0.47 | $0.00112 | 236 |
| parent | deepseek-v4-flash | 224 | 12 | 45% (51/114) | 100% (51/51) | 0% (0/110) | 0.44 | $0.00073 | 236 |
| parent | deepseek-v4-flash-0731 | 233 | 3 | 43% (53/122) | 100% (53/53) | 0% (0/111) | 0.42 | $0.00043 | 236 |
| parent | mercury-3 | 233 | 3 | 45% (54/120) | 100% (54/54) | 0% (0/113) | 0.44 | $0.00050 | 236 |
| parent | ling-3.0-flash | 229 | 7 | 43% (50/117) | 100% (50/50) | 0% (0/112) | 0.42 | $0.00016 | 236 |
| parent | ling-3.1-flash | 231 | 5 | 50% (60/120) | 100% (60/60) | 0% (0/111) | 0.49 | $0.00058 | 236 |
| parent | gpt-6-luna | 236 | 0 | 46% (56/122) | 93% (56/60) | 4% (4/114) | 0.42 | $0.00052 | 236 |
| parent | laguna-s-2.1 | 224 | 12 | 40% (46/114) | 100% (46/46) | 0% (0/110) | 0.40 | $0.00052 | 236 |
| parent | qwen3.7-flash | 229 | 7 | 45% (53/117) | 100% (53/53) | 0% (0/112) | 0.45 | $0.00027 | 236 |
| parent | glm-4.7-flash | 217 | 19 | 46% (52/112) | 98% (52/53) | 1% (1/105) | 0.45 | $0.00069 | 236 |

## cf5, stage-5 subset (real + degraded, minus stray-edit copies of explore tasks): 204 runs, 90 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 204 | 0 | 57% (51/90) | 82% (51/62) | 10% (11/114) | 0.49 | – | 205 |
| grader | gemini-3.8-flash | 204 | 0 | 51% (46/90) | 98% (46/47) | 1% (1/114) | 0.53 | $0.00241 | 204 |
| grader | gemini-4-argon | 204 | 0 | 51% (46/90) | 96% (46/48) | 2% (2/114) | 0.52 | $0.00321 | 204 |
| grader | gemma-4-26b-a4b-qat | 202 | 2 | 49% (44/90) | 98% (44/45) | 1% (1/112) | 0.50 | – | 227 |
| parent | qwen3.5-9b | 204 | 0 | 58% (52/90) | 91% (52/57) | 4% (5/114) | 0.56 | – | 234 |
| parent | gemini-3.8-flash | 204 | 0 | 63% (57/90) | 100% (57/57) | 0% (0/114) | 0.66 | $0.00918 | 232 |
| parent | gemini-4-argon | 204 | 0 | 69% (62/90) | 100% (62/62) | 0% (0/114) | 0.71 | $0.01408 | 208 |
| parent | gemma-4-26b-a4b-qat | 204 | 0 | 61% (55/90) | 98% (55/56) | 1% (1/114) | 0.63 | – | 253 |
| parent | claude-haiku-5.5 | 204 | 0 | 67% (60/90) | 97% (60/62) | 2% (2/114) | 0.67 | $0.00112 | 204 |
| parent | deepseek-v4-flash | 193 | 11 | 61% (51/83) | 100% (51/51) | 0% (0/110) | 0.64 | $0.00075 | 204 |
| parent | deepseek-v4-flash-0731 | 201 | 3 | 59% (53/90) | 100% (53/53) | 0% (0/111) | 0.61 | $0.00044 | 204 |
| parent | mercury-3 | 202 | 2 | 61% (54/89) | 100% (54/54) | 0% (0/113) | 0.63 | $0.00051 | 204 |
| parent | ling-3.0-flash | 199 | 5 | 57% (50/87) | 100% (50/50) | 0% (0/112) | 0.60 | $0.00017 | 204 |
| parent | ling-3.1-flash | 201 | 3 | 67% (60/90) | 100% (60/60) | 0% (0/111) | 0.69 | $0.00059 | 204 |
| parent | gpt-6-luna | 204 | 0 | 61% (55/90) | 93% (55/59) | 4% (4/114) | 0.60 | $0.00051 | 204 |
| parent | laguna-s-2.1 | 193 | 11 | 55% (46/83) | 100% (46/46) | 0% (0/110) | 0.59 | $0.00053 | 204 |
| parent | qwen3.7-flash | 197 | 7 | 62% (53/85) | 100% (53/53) | 0% (0/112) | 0.65 | $0.00027 | 204 |
| parent | glm-4.7-flash | 190 | 14 | 60% (51/85) | 98% (51/52) | 1% (1/105) | 0.61 | $0.00070 | 204 |

## cf3a (mercury-2.5 runs), real runs only: 140 runs, 12 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3-coder-30b | 89 | 0 | 27% (3/11) | 21% (3/14) | 14% (11/78) | 0.12 | – | 89 |
| grader | claude-haiku-5.5 | 140 | 0 | 58% (7/12) | 24% (7/29) | 17% (22/128) | 0.25 | $0.00048 | 140 |
| grader | deepseek-v4-flash-0731#off | 58 | 82 | 25% (2/8) | 22% (2/9) | 14% (7/50) | 0.10 | $0.00012 | 140 |
| parent | qwen3-coder-30b | 86 | 2 | 9% (1/11) | 100% (1/1) | 0% (0/75) | 0.15 | – | 88 |
| parent | claude-haiku-5.5 | 140 | 0 | 25% (3/12) | 33% (3/9) | 5% (6/128) | 0.23 | $0.00146 | 140 |
| parent | deepseek-v4-flash-0731#off | 137 | 3 | 44% (4/9) | 67% (4/6) | 2% (2/128) | 0.51 | $0.00046 | 140 |
