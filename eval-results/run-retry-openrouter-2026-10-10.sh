#!/bin/bash
# B on OpenRouter: the fault proxy in front of OpenRouter drops large write calls served by SiliconFlow (one of
# Qwen3-Coder 30B's two providers; the other is Amazon Bedrock). The agent should re-send with provider.ignore
# ["SiliconFlow"], and no later reply in that run should come from SiliconFlow. Cap $0.45 for this run ($0.50 in all, with run 1, which had a proxy bug: its fake empty replies named no provider). 2026-10-10.
cd ~/git/kurtkode
D=2026-10-10
python3 spike/fault_proxy.py --port 18082 --arm tailored --upstream https://openrouter.ai/api/v1 --faulty SiliconFlow \
    2> eval-results/retry-openrouter-$D-proxy.log &
P=$!
sleep 1
AgentCore/.build/release/kurtkode-eval --endpoint proxy=http://127.0.0.1:18082/v1 --key-from openrouter \
    --models proxy:qwen/qwen3-coder-30b-a3b-instruct --scenarios long-doc --trials 2 --max-cost 0.45 --sandbox fullAuto \
    --out eval-results/retry-openrouter-$D.json --transcripts eval-results/retry-openrouter-$D-transcripts \
    > eval-results/retry-openrouter-$D.log 2>&1
kill $P
echo ALL_DONE
