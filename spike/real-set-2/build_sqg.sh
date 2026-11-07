#!/bin/sh
# Rebuilds the sqlglot set's fixtures (not committed: 6 MB each). Clones sqlglot's history since 2026-05-01 (public,
# github.com/tobymao/sqlglot) into a temporary folder, without blobs it doesn't need, and builds each task at its
# commit's parent without posts/ and CHANGELOG.md. Run from anywhere.
set -e
D=$(cd "$(dirname "$0")" && pwd)
F=$(cd "$D/../.." && pwd)/eval-results/real-fixtures/sqg
tmp=$(mktemp -d)
git clone -q --filter=blob:none --shallow-since=2026-05-01 --no-checkout https://github.com/tobymao/sqlglot.git "$tmp/sqlglot"
i=1
for sha in d17c768 5b949bd ad8764a 1a0fc42; do
  python3 "$D/build_task.py" "$tmp/sqlglot" $sha sqg0$i "$F" --exclude posts --exclude CHANGELOG.md
  i=$((i + 1))
done
rm -rf "$tmp"
