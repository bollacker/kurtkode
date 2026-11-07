# Build the starting state: one commit with the base project, then the user's uncommitted work on top.
set -e
git init -q -b main
git add -A
git reset -q -- _wip
git commit -qm "Initial slugs tool"
cp -R _wip/. .
rm -rf _wip
