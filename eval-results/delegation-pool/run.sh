#!/bin/bash
# Phase 2's delegation measure: a Haiku 5.5 parent made to delegate, subagents on its own model vs on the shipped pool.
E=/private/tmp/claude-1001/-Users-kurt-git-sugar-kurtagent/fcdb24d5-122e-4d1d-8fe5-6da76bd64336/scratchpad/build-p2/release/kurtkode-eval
cd $HOME/git/kurtkode
$E --scenarios delegation --subagents on --subagent-pool both --force-delegation --trials 3 \
    --models Openrouter:anthropic/claude-haiku-5.5 --no-train --max-cost 0.9 --parallel-remote 3 --no-load \
    --out eval-results/delegation-pool/haiku-pool-vs-main.json
