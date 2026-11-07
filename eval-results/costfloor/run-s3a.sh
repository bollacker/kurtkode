#!/bin/bash
# Stage 3a: the hard tier (3 trials) and bank trials 2-3 for the finalists in models-s3a.txt. Own cap $25 in all;
# pass the remaining cap as $1. Runs already recorded are skipped, so this can be rerun with more finalists.
cd ~/git/kurtkode
E=AgentCore/.build-cf/release/kurtkode-eval
COMMON="--models-file eval-results/costfloor/models-s3a.txt --no-train --trials 3 --models-at-once 4 --parallel-remote 3 --own-cost --key-limit 2714 --no-load"
$E --bank hard --record cf3a --max-cost "$1" $COMMON
S1="find-reserve-def,insufficient-status,fix-calc,add-median,write-report-tests,review-shop-diff"
$E --bank "$S1" --record cf1 --max-cost "$2" $COMMON
$E --bank "$(cat eval-results/costfloor/s2-tasks.txt)" --record cf2 --max-cost "$3" $COMMON
