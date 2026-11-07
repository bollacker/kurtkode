# Starting state: two commits of the base project on main, then a previous session's uncommitted median work
# (stats.py, cli.py, tests) and its untracked scratch NOTES.md.
set -e
git init -q -b main
git add -A
git reset -q -- _wip
git commit -qm "numstat: mean of a file of numbers"
git checkout -qb median-12
cp -R _wip/. .
rm -rf _wip
