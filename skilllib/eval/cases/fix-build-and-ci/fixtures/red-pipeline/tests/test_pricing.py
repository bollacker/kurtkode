import unittest
from decimal import Decimal
from invoicer.pricing import money, line_total, invoice_total


class TestPricing(unittest.TestCase):
    def test_money_rounds_half_up(self):
        self.assertEqual(money("2.345"), Decimal("2.35"))

    def test_line_total(self):
        self.assertEqual(line_total(3, "1.10"), Decimal("3.30"))

    def test_invoice_total(self):
        self.assertEqual(invoice_total([(2, "5.00"), (1, "0.99")]), Decimal("10.99"))

    def test_empty_invoice(self):
        self.assertEqual(invoice_total([]), Decimal("0.00"))
