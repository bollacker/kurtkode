import unittest

from shop.pricing import bulk_percent, line_total


class PricingTest(unittest.TestCase):
    def test_line_total(self):
        self.assertEqual(line_total(1250, 3), 3750)

    def test_rejects_zero_qty(self):
        with self.assertRaises(ValueError):
            line_total(1250, 0)

    def test_ten_percent_from_fifty(self):
        self.assertEqual(bulk_percent(60), 10)

    def test_discount_rounds_down_to_whole_cents(self):
        # 11 x 45 = 495 cents; 5% is 24.75, rounded down to 24.
        self.assertEqual(line_total(45, 11), 471)
