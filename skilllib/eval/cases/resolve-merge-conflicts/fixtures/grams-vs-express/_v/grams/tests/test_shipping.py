import unittest

from parcel.shipping import shipping_cost


class ShippingTest(unittest.TestCase):
    def test_domestic(self):
        self.assertEqual(shipping_cost(2500, "domestic"), 8.0)

    def test_intl(self):
        self.assertEqual(shipping_cost(1000, "intl"), 16.2)
