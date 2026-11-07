# Reference review: both planted bugs, verified; the round-down and search.py dismissed.
cat > REVIEW.md <<'MD'
Reviewed: main...bulk-discounts, 5 files. Ran: python3 -m unittest discover -s tests -t . (6 passed) and
python3 -c "from shop.orders import order_total; order_total([('Z9', 1)])" (TypeError).

## Findings
- shop/catalog.py:12 — blocker: find_item now returns None for an unknown sku, but shop/orders.py:10-15 still
  catches KeyError. Trigger: order_total([("Z9", 1)]). Result: TypeError on item["price_cents"] instead of
  (0, ["Z9"]). Fix: check for None in order_total.
- shop/pricing.py:10 — blocker: `qty > min_qty` gives no discount at exactly 10 (and 5% at exactly 50); the commit
  says 10 or more and 50 or more. Trigger: bulk_percent(10) == 0. Fix: `>=`.

## Checked, not a problem
- Discounts are rounded down on purpose (commit message, test_discount_rounds_down_to_whole_cents).
- search.search only looks up skus taken from ITEMS, so find_item cannot return None there.
MD
