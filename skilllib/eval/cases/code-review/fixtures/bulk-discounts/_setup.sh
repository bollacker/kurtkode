# main: the base; branch bulk-discounts: the change to review (left checked out).
set -e
git init -q -b main
git add -A -- . ':(exclude)_branch'
git commit -qm "Catalog, pricing and order totals"
git checkout -q -b bulk-discounts
cp -R _branch/. .
rm -rf _branch
git add -A
git commit -q -F - <<'MSG'
Add bulk discounts and catalog search

Bulk discounts: 5% off a line of 10 or more units, 10% off 50 or more.
Discounts are rounded down to whole cents (finance asked for this: we never
give more than the advertised percent).

find_item now returns None for an unknown sku, so the search page can use it
without try/except.
MSG
