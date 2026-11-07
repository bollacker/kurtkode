import unittest
from shop.convert import convert


class TestConvert(unittest.TestCase):
    def test_usd_is_identity(self):
        self.assertEqual(convert(10, "USD"), 10)

    def test_eur(self):
        self.assertEqual(convert(100, "EUR"), 90.0)

    def test_gbp(self):
        self.assertEqual(convert(50, "GBP"), 40.0)
