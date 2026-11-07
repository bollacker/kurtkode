#!/bin/bash
# Phase 0 agent-loop matrix. Usage: ./run_matrix.sh gemma | qwen
# Each run writes spike/logs/<name>.log (unbuffered) and spike/results/<name>.json.
set -u
cd "$(dirname "$0")"
mkdir -p logs results
LMS=~/.cache/lm-studio/bin/lms
TRIALS=${TRIALS:-4}
export STEPS=20 MAX_TOKENS=4096 TURN_TIMEOUT=180 PYTHONUNBUFFERED=1

run() {  # run NAME MODEL VARIANT [SKIP_PROBES]
  echo "=== START $1 ($2, variant=$3)"
  VARIANT=$3 SKIP_PROBES=${4:-1} OUT=results/$1.json \
    python3 toolcall_spike.py "$2" --trials "$TRIALS" >logs/$1.log 2>&1
  echo "=== END $1 exit=$? :: $(grep -c 'ok=True' logs/$1.log)/$TRIALS ok :: $(grep -o 'outcome=[a-z_]*' logs/$1.log | sort | uniq -c | tr '\n' ' ')"
}

free_pct() { memory_pressure -Q | awk '/free percentage/ {sub("%","",$NF); print $NF}'; }

load() {  # load MODEL — alone, under its own id (no --identifier), explicit context, one slot
  $LMS unload --all >/dev/null 2>&1
  sleep 3
  local f; f=$(free_pct)
  echo "=== LOAD $1 (free memory ${f}%)"
  if [ "$f" -lt 30 ]; then echo "=== ABORT: only ${f}% memory free"; exit 3; fi
  # --parallel 1: each parallel slot reserves its own KV cache; 4 slots x 32k ballooned llama-server RSS
  $LMS load "$1" --context-length 32768 --parallel 1 -y 2>&1 | tr '\r' '\n' | grep -E 'loaded|rror' | tail -1
  echo "=== LOADED $1 (free memory $(free_pct)%)"
}

case "${1:-}" in
  gemma)
    run gemma26_base   gemma26 base
    run gemma26_both   gemma26 both
    load google/gemma-4-12b-qat
    run gemma12_strict google/gemma-4-12b-qat strict 0
    $LMS unload google/gemma-4-12b-qat
    load gemma-4-e4b-it
    run gemma4b_strict gemma-4-e4b-it strict 0
    $LMS unload gemma-4-e4b-it
    ;;
  qwen)
    load qwen/qwen3-coder-30b
    run qwen30_base    qwen/qwen3-coder-30b base 0
    run qwen30_strict  qwen/qwen3-coder-30b strict
    run qwen30_both    qwen/qwen3-coder-30b both
    ;;
  *) echo "usage: $0 gemma|qwen"; exit 2 ;;
esac
echo "=== MATRIX DONE $1"
