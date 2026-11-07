#!/bin/sh
# Rebuilds the Go sets' fixtures (not committed: OPA's are about 10 MB each). Clones google/cel-go and
# open-policy-agent/opa (public, github.com) since 2026-05-01 without blobs it doesn't need, or uses CEL_REPO / OPA_REPO
# when set, and builds each task at its commit's parent. Go's tests sit beside the code, so the hidden tests are every
# changed *_test.go and testdata file. cel-go vendors its modules; OPA's are fetched into GOMODCACHE (`go mod download`
# runs none of their code). Needs Go on PATH; REAL_TASKS_PLAN.md "A second language" has the environment.
set -e
D=$(cd "$(dirname "$0")" && pwd)
F=$(cd "$D/../.." && pwd)/eval-results/real-fixtures
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GOTOOLCHAIN=local GOMODCACHE=${GOMODCACHE:-$HOME/sdk/gomodcache} GOPATH=${GOPATH:-$HOME/sdk/gopath}
export GOCACHE=${GOCACHE:-$HOME/sdk/gocache-host}
clone() { git clone -q --filter=blob:none --shallow-since=2026-05-01 --no-checkout "https://github.com/$1.git" "$2"; }
CEL=${CEL_REPO:-$tmp/cel-go}; [ -d "$CEL" ] || clone google/cel-go "$CEL"
OPA=${OPA_REPO:-$tmp/opa}; [ -d "$OPA" ] || clone open-policy-agent/opa "$OPA"
TESTS="--tests :(glob)**/*_test.go --tests :(glob)**/testdata/**"
i=1
for sha in af38f75 41d9149 be9dacd 13cff33 0175dbb; do
  # Before 12328e5 (2026-07-15) json.encode's output order varied, so ext's TestEncoders failed now and then: the
  # two parents that have the encoder but are older than the fix get it (cel04's predates the encoder).
  case $sha in 41d9149|be9dacd) json="--patch $D/cel-json-determinism-12328e5.diff" ;; *) json= ;; esac
  python3 "$D/build_task.py" "$CEL" $sha cel0$i "$F/cel" $TESTS $json
  i=$((i + 1))
done
i=1
for sha in f6e3d5d0 01eefbab 85b62162 63f54da4 ae4ed955 23745504; do
  # Before b9a27784 (2026-09-22) v1/topdown's tests started a server at init, which the sandbox refuses, so the whole
  # package failed; before 517c5cb3 (2026-10-09) the cases that use it sat inside TestTopDownPartialEval, so skipping
  # them by name meant skipping it all. The two older parents get both upstream test-only changes.
  case $sha in
    ae4ed955|23745504) lazy="--patch $D/opa-lazy-testserver-b9a27784.diff --patch $D/opa-split-loopback-517c5cb3.diff" ;;
    *) lazy= ;;
  esac
  python3 "$D/build_task.py" "$OPA" $sha opa0$i "$F/opa" $TESTS --mod-download --exclude docs --exclude SECURITY_AUDIT.pdf \
    --exclude logo --exclude proposals --add "$D/opa-run-tests.sh:run-tests.sh" $lazy
  i=$((i + 1))
done
python3 "$D/go_hidden_fixes.py" "$F"
