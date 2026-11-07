# History: a base commit; branch "express" adds express shipping and a checkout quote; main switches all weights
# to integer grams. Then, on main, `git merge express` stops with conflicts (left in progress for the agent).
set -e
git init -q -b main
mv _v .git/kk_versions
V=.git/kk_versions
cp -R $V/base/. .
git add -A
git commit -qm "Parcel shipping prices and order totals"
git checkout -qb express
cp $V/express/parcel/shipping.py $V/express/parcel/orders.py parcel/
cp $V/express/tests/test_shipping.py $V/express/tests/test_orders.py tests/
git add -A
git commit -qm "Add express shipping" -m "Express: 1.5x the standard price, and parcels are billed as at least 1 kg (carrier minimum)."
cp $V/express/parcel/quote.py parcel/
cp $V/express/tests/test_quote.py tests/
git add -A
git commit -qm "Show standard and express prices on the checkout page" -m "quick_quote() returns both options for one parcel."
git checkout -q main
cp -R $V/grams/. .
git add -A
git commit -qm "Store weights as integer grams" -m "The warehouse scales report grams and float kilograms caused rounding differences on invoices. shipping_cost and order_total now take grams (weight_g)."
rm -rf $V
git merge express -m "Merge branch 'express'" >/dev/null 2>&1 || true
test -n "$(git ls-files -u)"
