# Reference: characterization tests first, then the function split into steps that keep every quirk
# (lines counts qty-0 lines, the last counted line's category decides the fragile surcharge, coupon precedence).
cat > tests/test_billing_characterization.py <<'PY'
"""Pins compute_invoice's behavior as it was before the refactor (observed outputs, not a spec)."""
import unittest

from shop.billing import compute_invoice

CASES = [
    ({}, {"subtotal": 0.0, "discount": 0.0, "shipping": 4.99, "tax": 0.0, "total": 4.99}),
    ({"items": [{"price": 10, "category": "fragile"}, {"price": 5}]},
     {"subtotal": 15.0, "discount": 0.0, "shipping": 4.99, "tax": 0.0, "total": 19.99}),
    ({"items": [{"price": 5}, {"price": 10, "category": "fragile"}]},
     {"subtotal": 15.0, "discount": 0.0, "shipping": 7.99, "tax": 0.0, "total": 22.99}),
    ({"items": [{"price": 10}, {"price": 10, "qty": 0}, {"price": 10, "qty": 0}], "member": True},
     {"subtotal": 10.0, "discount": 0.0, "shipping": 0.0, "tax": 0.0, "total": 10.0}),
    ({"items": [{"price": 10}], "coupon": "VIP", "region": "NY"},
     {"subtotal": 10.0, "discount": 1.0, "shipping": 4.99, "tax": 0.56, "total": 14.55}),
    ({"items": [{"price": 20, "qty": 2}], "coupon": "SAVE10"},
     {"subtotal": 40.0, "discount": 0.0, "shipping": 4.99, "tax": 0.0, "total": 44.99}),
]


class Characterization(unittest.TestCase):
    def test_pinned_outputs(self):
        for order, want in CASES:
            with self.subTest(order=order):
                got = compute_invoice(order)
                self.assertEqual(got.keys(), want.keys())
                for k in want:
                    self.assertAlmostEqual(got[k], want[k], places=9)


if __name__ == "__main__":
    unittest.main()
PY
python3 -m unittest -q tests.test_billing_characterization 2>/dev/null || { echo "characterization tests fail on the original"; exit 1; }
cat > shop/billing.py <<'PY'
"""Invoice totals. Issued invoices are re-computed from this code for audits, so results must not drift."""

TAX = {"CA": 0.0725, "NY": 0.04, "OR": 0.0, "TX": 0.0625}
TAXED_SHIPPING = {"NY", "TX"}


def _unit_price(item, member):
    category = item.get("category", "general")
    price = item["price"]
    if category == "clearance":
        return price * 0.5
    if category == "food" and member:
        return price * 0.9
    return price


def _sum_items(items, member):
    """Returns subtotal, line count, weight and the category of the last counted line.
    Note: lines includes lines with qty <= 0 (they are otherwise skipped). Kept as is: totals must not drift."""
    subtotal, weight, last_category = 0.0, 0.0, None
    for item in items:
        qty = item.get("qty", 1)
        if qty <= 0:
            continue
        last_category = item.get("category", "general")
        subtotal += _unit_price(item, member) * qty
        weight += item.get("weight", 0.5) * qty
    return round(subtotal, 2), len(items), weight, last_category


def _discount(subtotal, code, member):
    discount = 0.0
    if (code == "SAVE10" and subtotal >= 50) or code == "VIP":
        discount = round(subtotal * 0.1, 2)
    elif code == "FLAT5":
        discount = 5.0 if subtotal > 5 else subtotal
    if member and discount == 0 and subtotal >= 100:
        discount = round(subtotal * 0.05, 2)
    return discount


def _shipping(net, member, lines, weight, last_category):
    # Known quirk, kept: the fragile surcharge depends on the LAST counted line only.
    if net >= 75 or (member and lines >= 3):
        shipping = 0.0
    else:
        shipping = 4.99
        if weight > 10:
            shipping = shipping + (weight - 10) * 0.75
        if lines > 4:
            shipping += 2.0
        shipping = round(shipping, 2)
    if last_category == "fragile":
        shipping += 3.0
    return shipping


def _tax(region, net, shipping):
    rate = TAX.get(region, 0.05)
    base = net + shipping if region in TAXED_SHIPPING else net
    return round(base * rate, 2)


def compute_invoice(order):
    items = order.get("items", [])
    region = order.get("region", "OR")
    member = order.get("member", False)
    subtotal, lines, weight, last_category = _sum_items(items, member)
    discount = _discount(subtotal, order.get("coupon"), member)
    shipping = _shipping(subtotal - discount, member, lines, weight, last_category)
    tax = _tax(region, subtotal - discount, shipping)
    total = round(subtotal - discount + shipping + tax, 2)
    return {"subtotal": subtotal, "discount": discount, "shipping": shipping, "tax": tax, "total": total}
PY
python3 -m unittest -q 2>/dev/null
