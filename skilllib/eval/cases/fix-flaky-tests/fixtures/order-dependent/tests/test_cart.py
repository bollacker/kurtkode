import unittest
from shop.cart import Cart


class TestCart(unittest.TestCase):
    def test_usd_total(self):
        c = Cart()
        c.add("pen", 1.5, 4)
        c.add("pad", 3.0)
        self.assertEqual(c.total(), 9.0)

    def test_gbp_total(self):
        c = Cart("GBP")
        c.add("mug", 10.0, 2)
        self.assertEqual(c.total(), 16.0)

    def test_empty(self):
        self.assertEqual(Cart("EUR").total(), 0)
