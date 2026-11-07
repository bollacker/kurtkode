#!/bin/sh
# Rebuilds the kurtkode sets' fixtures (not committed: each is the repository's own tracked tree at a commit, 3–12 MB).
# kk: hidden-test edit tasks at each commit's parent, with 28e9843's fix for a process wait that sometimes hangs the
# suite (the commits before it hung kk02's gold 7 times in 8); kkq: lookups at one commit. Run from anywhere.
set -e
D=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$D/../.." && pwd)
F=$REPO/eval-results/real-fixtures
i=1
for sha in f684795 2cbf82d 40b78d5 b1212ff ef71941; do
  fix=""
  git -C "$REPO" merge-base --is-ancestor 28e9843 $sha ||
    fix="--patch $D/hangfix-28e9843.diff --add $D/ProcessExit.swift:AgentCore/Sources/AgentCore/Tools/ProcessExit.swift"
  python3 "$D/build_task.py" "$REPO" $sha kk0$i "$F/kk" --tests AgentCore/Tests/ --exclude eval-results --exclude spike \
    --add "$D/kk-run-tests.sh:run-tests.sh" $fix
  i=$((i + 1))
done
LOOKUP=eb19878
tmp=$(mktemp -d)
git -C "$REPO" archive $LOOKUP | tar -x -C "$tmp"
rm -rf "$tmp/eval-results" "$tmp/spike"
for id in kkq01 kkq02 kkq03; do tar -czf "$F/kkq/$id.tgz" -C "$tmp" .; done
rm -rf "$tmp"
