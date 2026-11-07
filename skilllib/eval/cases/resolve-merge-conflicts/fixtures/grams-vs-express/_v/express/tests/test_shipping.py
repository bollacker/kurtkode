import unittest

from parcel.shipping import shipping_cost


class ShippingTest(unittest.TestCase):
    def test_domestic(self):
        self.assertEqual(shipping_cost(2.5, "domestic"), 8.0)

    def test_intl(self):
        self.assertEqual(shipping_cost(1.0, "intl"), 16.2)

    def test_express_light_parcel_billed_as_one_kg(self):
        self.assertEqual(shipping_cost(0.5, "domestic", express=True), 9.3)

    def test_express_heavy_parcel(self):
        self.assertEqual(shipping_cost(2.0, "domestic", express=True), 11.1)
