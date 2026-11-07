import unittest

from parcel.orders import order_total


class OrdersTest(unittest.TestCase):
    def test_total(self):
        self.assertEqual(order_total([(10.0, 0.3), (5.0, 0.2)], "domestic"), 20.6)

    def test_total_express(self):
        self.assertEqual(order_total([(10.0, 0.3), (5.0, 0.2)], "domestic", express=True), 24.3)
