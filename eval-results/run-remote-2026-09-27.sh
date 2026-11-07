#!/bin/bash
# Remote (OpenRouter) eval chain, 2026-09-27. Run from the repo root. Caps are per invocation; total < $2.
set -u
E=AgentCore/.build/release/kurtkode-eval
R=eval-results
echo "### A/B gpt-oss explain-repo"
$E --models openrouter:openai/gpt-oss-120b --scenarios explain-repo --trials 3 --max-cost 0.10 \
   --out $R/gptoss-ab-profile.json --transcripts $R/gptoss-ab-transcripts/profile
$E --models openrouter:openai/gpt-oss-120b --scenarios explain-repo --trials 3 --max-cost 0.10 --no-profiles \
   --out $R/gptoss-ab-noprofile.json --transcripts $R/gptoss-ab-transcripts/noprofile
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
