import unittest

from shop.pricing import line_total


class PricingTest(unittest.TestCase):
    def test_line_total(self):
        self.assertEqual(line_total(1250, 3), 3750)

    def test_rejects_zero_qty(self):
        with self.assertRaises(ValueError):
            line_total(1250, 0)
