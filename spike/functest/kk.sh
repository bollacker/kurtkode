#!/bin/bash
# usage: kk.sh VAR=val ... ; launches the app (Debug unless APP is set) with env vars; prints the new instance's pid
APP=${APP:-$HOME/git/kurtkode/build/DerivedData/Build/Products/Debug/kurtkode.app}
before=" $(pgrep -x kurtkode | tr '\n' ' ') "
# Test instances run in the background: never let them post notifications (or macOS's permission question).
args=(--env KURTKODE_NO_NOTIFY=1); for kv in "$@"; do args+=(--env "$kv"); done
open -n -g "${args[@]}" "$APP"
for i in $(seq 1 20); do
  sleep 0.5
  for p in $(pgrep -x kurtkode); do
    case "$before" in *" $p "*) continue;; esac
    ps -o comm= -p $p | grep -q "$APP" && { sleep 1.5; echo $p; exit 0; }
  done
done
echo "kk.sh: no new instance" >&2; exit 1
