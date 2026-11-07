#!/bin/bash
# 16.10 streaming soak: 10 launches of the PerfDD app, each a new plain chat with one streamed reply (REPLY, default
# ./reply.md: make ~60 KB of Markdown with headings, lists, code and tables) at 110 tok/s. Watches each instance's hang
# log; samples the app once per run, on its first stall >= 1 s (sampling more feeds itself: a sample stalls the app).
# Writes soak.log and sample-RUN-*.txt next to itself.
D=$(cd "$(dirname "$0")" && pwd); FT=$D; REPLY=${REPLY:-$D/reply.md}
APP=${APP:-$HOME/git/kurtkode/build/PerfDD/Build/Products/Release/kurtkode.app}
python3 $HOME/git/kurtkode/spike/mock_stream_server.py --port ${PORT:-18090} --text $REPLY --tps 110 & MOCK=$!
echo "start $(date +%s)" > $D/soak.log
for run in $(seq 1 ${RUNS:-10}); do
  t0=$(date +%s)
  pid=$(APP=$APP $FT/kk.sh KURTKODE_EXTRA_ENDPOINT=Mock=http://127.0.0.1:${PORT:-18090}/v1 'KURTKODE_MODEL=Mock|mock' "KURTKODE_AUTOSEND=soak-${TAG:-x}-$run-only")
  echo "run $run pid $pid t0 $t0" >> $D/soak.log
  # sampler: on a hang line >= 1 s from this pid, sample it at once
  ( log stream --style compact --predicate "subsystem == \"org.mlcommons.kurt.kurtkode\" AND category == \"hang\" AND processID == $pid" 2>/dev/null | while read -r line; do
      echo "HANG $line" >> $D/soak.log
      ms=$(echo "$line" | grep -oE '[0-9]+ ms' | head -1 | grep -oE '[0-9]+')
      [ -n "$ms" ] && [ "$ms" -ge 1000 ] && [ ! -e $D/sample-$run.txt ] && sample $pid 3 -file $D/sample-$run.txt >/dev/null 2>&1
    done ) & LS=$!
  # wait until the session has two finished assistant replies (max 8 min)
  for i in $(seq 1 400); do
    sleep 1
    f=$(grep -l "soak-${TAG:-x}-$run-only" ~/Library/Application\ Support/kurtkode/sessions/_chats*/*.jsonl 2>/dev/null | head -1)
    [ -n "$f" ] && [ "$(grep -c '"finishReason"' "$f" 2>/dev/null)" -ge 1 ] && break
  done
  echo "run $run done after $(( $(date +%s) - t0 )) s file $f" >> $D/soak.log
  sleep 3
  echo "run $run cpu $(ps -o cputime= -p $pid | tr -d ' ')" >> $D/soak.log
  kill $pid; kill $LS 2>/dev/null; pkill -P $LS 2>/dev/null
  # `log stream` outlives the subshell (50 were left running after session 7): stop it by its predicate.
  pkill -f "category == \"hang\" AND processID == $pid\$" 2>/dev/null
  sleep 2
done
kill $MOCK
echo "end $(date +%s)" >> $D/soak.log
