#!/bin/bash
# Cost-floor shortlist again (item 3): Phase 1 tools + Round 5 fixes + built-in skills, 10 trials, bank and hard tier.
S=/private/tmp/claude-1001/-Users-kurt-git-sugar-kurtagent/fcdb24d5-122e-4d1d-8fe5-6da76bd64336/scratchpad
E=$S/build-cf6/release/kurtkode-eval
cd $HOME/git/kurtkode
COMMON="--models-file $S/models-cf6.txt --no-train --skills builtin --trials 10 --models-at-once 3 --parallel-remote 3 --own-cost --key-limit 2620 --no-load"
echo "=== bank $(date)"
$E --bank all --record eval-results/runs/cf6 --max-cost 2.8 $COMMON
echo "=== hard $(date)"
$E --bank hard --record eval-results/runs/cf6 --max-cost 1.2 $COMMON
echo "=== done $(date)"
