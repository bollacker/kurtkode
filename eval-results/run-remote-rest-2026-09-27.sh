#!/bin/bash
# Rest of run-remote-2026-09-27.sh after the A/B (the chain was stopped while a leftover app used LM Studio).
set -u
E=AgentCore/.build/release/kurtkode-eval
R=eval-results
while pgrep -f "kurtkode-eval --models openrouter:openai/gpt-oss-120b --scenarios explain-repo" >/dev/null; do sleep 5; done
echo "### long-doc remote"
$E --models openrouter:qwen/qwen3-coder-30b-a3b-instruct,openrouter:google/gemma-4-26b-a4b-it,openrouter:qwen/qwen3-coder,openrouter:openai/gpt-oss-120b \
   --scenarios long-doc --trials 2 --max-cost 1.20 --out $R/remote-longdoc-2026-09-27.json --transcripts $R/remote-transcripts
echo "### switch S1 fix-tests"
$E --switch 'lmstudio:qwen/qwen3-coder-30b>openrouter:qwen/qwen3-coder-30b-a3b-instruct,openrouter:qwen/qwen3-coder-30b-a3b-instruct>lmstudio:mistralai/devstral-small-2-2512,openrouter:openai/gpt-oss-120b>lmstudio:google/gemma-4-12b-qat' \
   --scenarios fix-tests --trials 2 --switch-after 3 --max-cost 0.40 --out $R/switch-remote-fix-2026-09-27.json --transcripts $R/switch-remote-transcripts
echo "### switch S2 long-doc"
$E --switch 'lmstudio:qwen/qwen3-coder-30b>openrouter:qwen/qwen3-coder-30b-a3b-instruct' \
   --scenarios long-doc --trials 2 --switch-after 15 --max-cost 0.15 --out $R/switch-remote-longdoc-2026-09-27.json --transcripts $R/switch-remote-transcripts
echo "### CHAIN DONE"
