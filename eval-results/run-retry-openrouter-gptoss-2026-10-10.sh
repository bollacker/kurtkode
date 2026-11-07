#!/bin/bash
# B on OpenRouter with gpt-oss-120b (19 tool-capable providers): the fault proxy drops large write calls served by
# five of the cheap providers. Each that loses a reply should be added to provider.ignore for the rest of the run,
# and later replies should come from the others. Cap $0.47 (the rest of the approved $0.50). 2026-10-10.
cd ~/git/kurtkode
D=2026-10-10
python3 spike/fault_proxy.py --port 18083 --arm tailored --upstream https://openrouter.ai/api/v1 \
    --faulty Venice,CoreWeave,DekaLLM,AkashML,DeepInfra 2> eval-results/retry-gptoss-$D-proxy.log &
P=$!
sleep 1
AgentCore/.build/release/kurtkode-eval --endpoint proxy=http://127.0.0.1:18083/v1 --key-from openrouter \
    --models proxy:openai/gpt-oss-120b --scenarios long-doc --trials 2 --max-cost 0.47 --sandbox fullAuto \
    --out eval-results/retry-gptoss-$D.json --transcripts eval-results/retry-gptoss-$D-transcripts \
    > eval-results/retry-gptoss-$D.log 2>&1
kill $P
echo ALL_DONE
