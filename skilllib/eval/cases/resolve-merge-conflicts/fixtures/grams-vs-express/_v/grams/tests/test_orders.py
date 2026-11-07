import unittest

from parcel.orders import order_total


class OrdersTest(unittest.TestCase):
    def test_total(self):
        self.assertEqual(order_total([(10.0, 300), (5.0, 200)], "domestic"), 20.6)
