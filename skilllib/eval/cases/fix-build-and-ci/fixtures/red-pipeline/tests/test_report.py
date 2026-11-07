import unittest
from decimal import Decimal
from invoicer.report import convert, render


class TestReport(unittest.TestCase):
    def test_usd_is_identity(self):
        self.assertEqual(convert(Decimal("12.50"), "USD"), Decimal("12.50"))

    def test_convert_gbp(self):
        self.assertEqual(convert(Decimal("100"), "GBP"), Decimal("79.00"))

    def test_convert_eur(self):
        self.assertEqual(convert(Decimal("100"), "EUR"), Decimal("108.00"))

    def test_render_jpy(self):
        self.assertTrue(render([(1, "10.00")], "JPY").endswith("TOTAL 1512.00 JPY"))

    def test_render_lists_lines(self):
        self.assertIn("2 x 1.50 = 3.00", render([(2, "1.50")]))
