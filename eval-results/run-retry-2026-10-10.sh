#!/bin/bash
# B measurement: long-doc through the fault proxy, local Qwen3-Coder 30B. 2026-10-10.
cd ~/git/kurtkode
D=$(date +%Y-%m-%d)
E=AgentCore/.build/release/kurtkode-eval
python3 spike/fault_proxy.py --port 18080 --arm tailored --providers Flaky,Solid --faulty Flaky 2> eval-results/retry-providers-$D-proxy.log &
P1=$!
sleep 1
$E --endpoint proxy=http://127.0.0.1:18080/v1 --models proxy:qwen/qwen3-coder-30b --scenarios long-doc --trials 3 --no-load \
   --out eval-results/retry-providers-$D.json --transcripts eval-results/retry-providers-$D-transcripts > eval-results/retry-providers-$D.log 2>&1
kill $P1
python3 spike/fault_proxy.py --port 18081 --arm tailored 2> eval-results/retry-fallback-$D-proxy.log &
P2=$!
sleep 1
$E --endpoint proxy=http://127.0.0.1:18081/v1 --models proxy:qwen/qwen3-coder-30b --scenarios long-doc --trials 3 --no-load \
   --fallback lmstudio:qwen/qwen3-coder-30b \
   --out eval-results/retry-fallback-$D.json --transcripts eval-results/retry-fallback-$D-transcripts > eval-results/retry-fallback-$D.log 2>&1
kill $P2
echo ALL_DONE
