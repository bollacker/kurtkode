import unittest

from billing import money
from billing.invoice import Invoice, Item, render
from billing.refunds import refund_cents


class InvoiceTest(unittest.TestCase):
    def test_render(self):
        inv = Invoice("A-1", [Item("Widget", 2, 1250), Item("Cable", 1, 399)])
        self.assertEqual(render(inv).splitlines(), [
            "Invoice A-1",
            "-" * 40,
            "2 x Widget                        $25.00",
            "1 x Cable                          $3.99",
            "-" * 40,
            "Total                             $28.99",
        ])

    def test_total(self):
        self.assertEqual(Invoice("A-2", [Item("Desk", 3, 15000)]).total_cents(), 45000)


class MoneyTest(unittest.TestCase):
    def test_fmt(self):
        self.assertEqual(money.fmt(1234567), "$12,345.67")
        self.assertEqual(money.fmt(-250), "-$2.50")

    def test_parse_roundtrip(self):
        self.assertEqual(money.parse(money.fmt(-123456)), -123456)


class RefundTest(unittest.TestCase):
    def test_restocking_fee(self):
        self.assertEqual(refund_cents(Item("Lamp", 1, 2990), 1, opened=True), 2541)


if __name__ == "__main__":
    unittest.main()
