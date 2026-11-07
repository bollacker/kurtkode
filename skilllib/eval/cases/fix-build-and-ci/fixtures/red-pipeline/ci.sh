#!/usr/bin/env bash
# CI entry point: the pipeline runs exactly `bash ci.sh`. Steps keep going after a failure so one run shows
# every problem; the run fails if any step failed.
set -uo pipefail
cd "$(dirname "$0")"
status=0
step() {
  local name=$1
  shift
  echo "::group::$name"
  echo "+ $*"
  if "$@"; then
    echo "step $name: ok"
  else
    echo "##[error]step $name failed (exit $?)"
    status=1
  fi
  echo "::endgroup::"
}
step lint python3 tools/lint.py invoicer
step build python3 tools/build_rates.py data/rates.csv build/rates.json
step test python3 -m unittest discover -s tests -t . -v
echo "CI finished with status $status"
exit $status
