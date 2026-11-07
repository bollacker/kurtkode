import unittest

from ledger.money import format_cents, parse_amount


class ParseAmount(unittest.TestCase):
    def test_values(self):
        self.assertEqual(parse_amount("12.34"), 1234)
        self.assertEqual(parse_amount("7"), 700)
        self.assertEqual(parse_amount("0.5"), 50)

    def test_rejects(self):
        for text in ["", "1.234", "-3", "abc", "1.x"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_amount(text)


class FormatCents(unittest.TestCase):
    def test_values(self):
        self.assertEqual(format_cents(1234), "$12.34")
        self.assertEqual(format_cents(-5), "-$0.05")
        self.assertEqual(format_cents(0), "$0.00")


if __name__ == "__main__":
    unittest.main()
