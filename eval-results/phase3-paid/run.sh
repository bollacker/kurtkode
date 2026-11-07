#!/bin/bash
# Phase 3's paid measurements (user's go-ahead 2026-10-26, cap $1.50 in all):
# (1) A7: delegation scenarios, a Haiku 5.5 parent on OpenRouter with pool subagents, no delegation instruction,
#     without and with kurtkode's forced delegation; (2) A4: Haiku 5.5 and deepseek-v4-flash-0731 (reasoning off) as
#     judges of mercury-2.5's 140 hard-tier runs (stored in cf3a's judgments).
E=$HOME/git/kurtkode/AgentCore/.build/debug/kurtkode-eval
cd $HOME/git/kurtkode
$E --scenarios delegation --subagents on --subagent-pool --kk-delegation both --trials 3 \
    --models Openrouter:anthropic/claude-haiku-5.5 --no-train --max-cost 0.6 --parallel-remote 3 --no-load \
    --out eval-results/phase3-paid/a7-haiku-kk-delegation.json > eval-results/phase3-paid/a7.log 2>&1 &
$E --judge cf3a --judges "Openrouter:anthropic/claude-haiku-5.5,Openrouter:deepseek/deepseek-v4-flash-0731#off" \
    --judge-paths parent,grader --judge-trials all --only-model mercury-2.5 --no-train --max-cost 0.9 --parallel-remote 4 \
    > eval-results/phase3-paid/a4-judges.log 2>&1 &
wait
