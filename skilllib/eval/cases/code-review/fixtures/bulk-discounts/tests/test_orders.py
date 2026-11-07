import unittest

from shop.orders import order_total


class OrdersTest(unittest.TestCase):
    def test_total_of_known_items(self):
        self.assertEqual(order_total([("A100", 2), ("B200", 1)]), (3399, []))
