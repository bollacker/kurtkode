#!/bin/bash
# Regolds a run set one task at a time, through a folder of symlinks per task (a whole-store regold of cf2 missed
# changes that per-task regolds catch; cause not found). Usage: spike/regold_by_task.sh cf1 cf2 ...
cd ~/git/kurtkode
TMP=$(mktemp -d)
for set in "$@"; do
  for task in $(ls eval-results/runs/$set | sed 's/__.*//' | sort -u); do
    d=$TMP/$set-$task; mkdir -p $d
    for r in eval-results/runs/$set/${task}__*; do ln -s "$PWD/$r" $d/; done
    n=$(KURTKODE_NO_KEYCHAIN=1 AgentCore/.build/debug/kurtkode-eval --regold $d 2>&1 | tail -1)
    echo "$set $task: $n"
  done
done
rm -rf $TMP
