# Reference resolution: keep grams (main) everywhere and port express (branch) to grams, including the
# cleanly merged quote.py and its test; express's 1 kg minimum becomes 1000 g.
set -e
cat > parcel/shipping.py <<'PY'
"""Shipping prices for parcels."""

RATES = {"domestic": 5.0, "intl": 15.0}  # flat part, dollars
PER_KG = 1.2  # dollars per kilogram
EXPRESS_FACTOR = 1.5  # express costs half as much again
EXPRESS_MIN_G = 1000  # express parcels are billed as at least 1 kg


def shipping_cost(weight_g, zone, express=False):
    """Price in dollars for a parcel of weight_g grams sent to zone ("domestic" or "intl").
    Express parcels are billed as at least EXPRESS_MIN_G and cost EXPRESS_FACTOR times as much."""
    if express:
        weight_g = max(weight_g, EXPRESS_MIN_G)
    cost = RATES[zone] + PER_KG * weight_g / 1000
    if express:
        cost *= EXPRESS_FACTOR
    return round(cost, 2)
PY
cat > parcel/orders.py <<'PY'
"""Order totals."""
from parcel.shipping import shipping_cost


def order_total(items, zone, express=False):
    """items: list of (price, weight_g) pairs, weights in grams. Returns goods plus shipping, in dollars."""
    goods = sum(price for price, _ in items)
    weight_g = sum(w for _, w in items)
    return round(goods + shipping_cost(weight_g=weight_g, zone=zone, express=express), 2)
PY
cat > parcel/quote.py <<'PY'
"""Shipping options shown on the checkout page."""
from parcel.shipping import shipping_cost


def quick_quote(weight_g, zone):
    """Both shipping options for one parcel of weight_g grams, in dollars."""
    return {
        "standard": shipping_cost(weight_g=weight_g, zone=zone),
        "express": shipping_cost(weight_g=weight_g, zone=zone, express=True),
    }
PY
cat > tests/test_shipping.py <<'PY'
import unittest

from parcel.shipping import shipping_cost


class ShippingTest(unittest.TestCase):
    def test_domestic(self):
        self.assertEqual(shipping_cost(2500, "domestic"), 8.0)

    def test_intl(self):
        self.assertEqual(shipping_cost(1000, "intl"), 16.2)

    def test_express_light_parcel_billed_as_one_kg(self):
        self.assertEqual(shipping_cost(500, "domestic", express=True), 9.3)

    def test_express_heavy_parcel(self):
        self.assertEqual(shipping_cost(2000, "domestic", express=True), 11.1)
PY
cat > tests/test_orders.py <<'PY'
import unittest

from parcel.orders import order_total


class OrdersTest(unittest.TestCase):
    def test_total(self):
        self.assertEqual(order_total([(10.0, 300), (5.0, 200)], "domestic"), 20.6)

    def test_total_express(self):
        self.assertEqual(order_total([(10.0, 300), (5.0, 200)], "domestic", express=True), 24.3)
PY
sed -i.bak 's/quick_quote(0.5, "domestic")/quick_quote(500, "domestic")/' tests/test_quote.py && rm tests/test_quote.py.bak
python3 -m unittest discover -s tests -t . -q
git add -A
git commit -q --no-edit
