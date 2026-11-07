#!/bin/bash
# Dropped-call nudge A/B, 2026-09-27: local Qwen3-Coder through spike/fault_proxy.py, which drops
# write_file/edit_file calls with more than 300 argument bytes. Arm "tailored" passes kurtkode's nudge
# through; arm "generic" rewrites it to the old "Your last reply was empty" text. Free (local model).
set -u
E=AgentCore/.build/release/kurtkode-eval
R=eval-results
for arm in tailored generic; do
  echo "### arm $arm"
  python3 spike/fault_proxy.py --port 18080 --arm $arm 2> $R/nudge-ab-proxy-$arm.log &
  P=$!; sleep 1
  $E --endpoint proxy=http://127.0.0.1:18080/v1 --models proxy:qwen/qwen3-coder-30b --scenarios long-doc --trials 3 \
     --out $R/nudge-ab-$arm-2026-09-27.json --transcripts $R/nudge-ab-transcripts/$arm
  kill $P; wait $P 2>/dev/null
  echo "proxy: $(tail -1 $R/nudge-ab-proxy-$arm.log)"
done
echo "### AB DONE"
