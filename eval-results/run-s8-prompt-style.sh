#!/bin/bash
# Session 8: detailed vs lean system prompt on Claude Haiku 5.5 and Gemini 3 Flash (all scenarios, 2 trials).
cd "$(dirname "$0")/.."
E=AgentCore/.build/release/kurtkode-eval
run() { # model style cap tag
  $E --models "$1" --prompt-style "$2" --scenarios all --trials 2 --no-load --max-cost "$3" \
     --out eval-results/s8-$4-$2.json --transcripts eval-results/s8-$4-$2-transcripts > eval-results/s8-$4-$2.log 2>&1
}
run anthropic:claude-haiku-5-5 detailed 0.5 haiku &
run anthropic:claude-haiku-5-5 lean 0.5 haiku &
run google-gemini:gemini-3-flash-preview detailed 1.0 gemini &
run google-gemini:gemini-3-flash-preview lean 1.0 gemini &
wait
echo all done
