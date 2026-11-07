# Builds the repo and the saved log of the failing CI run (ci-output.log, untracked).
git init -q -b main && git add -A && git commit -qm "Add EUR and JPY rates" 
{
  cat <<'HEAD'
Current runner version: '2.319.1'
Operating System: Ubuntu 22.04.4 LTS
##[group]Run actions/checkout@v4
Syncing repository: acme/invoicer
Retrying in 4 seconds: error: RPC failed; curl 56 GnuTLS recv error (-9)
Fetching the repository: done
Checking out the ref: refs/heads/main
##[endgroup]
##[group]Run actions/setup-python@v5
##[warning]Node.js 16 actions are deprecated. Please update to Node.js 20.
Successfully set up CPython (3.12.4)
Collected 0 errors from environment validation
##[endgroup]
##[group]Run bash ci.sh
HEAD
  bash ci.sh 2>&1
  cat <<'TAIL'
##[error]Process completed with exit code 1.
Post job cleanup.
[command]/usr/bin/git config --local --unset-all http.https://github.com/.extraheader
Cleaning up orphan processes
TAIL
} | awk '{ printf "2026-10-24T14:03:%02d.%07dZ %s\n", int(NR/6), NR*7919 % 10000000, $0 }' > ci-output.log
rm -rf build invoicer/__pycache__ tests/__pycache__
