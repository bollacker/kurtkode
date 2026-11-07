# Reference: discount through money.percent_of and money.fmt via the existing _line helper; tests added.
python3 - <<'PY'
p = "billing/invoice.py"
s = open(p).read()
s = s.replace("    items: list = field(default_factory=list)\n",
              "    items: list = field(default_factory=list)\n    discount_pct: int = 0\n")
s = s.replace("    def total_cents(self):\n        return self.subtotal_cents()\n",
              "    def discount_cents(self):\n"
              "        return money.percent_of(self.subtotal_cents(), self.discount_pct) if self.discount_pct else 0\n\n"
              "    def total_cents(self):\n        return self.subtotal_cents() - self.discount_cents()\n")
s = s.replace('    out.append("-" * WIDTH)\n    out.append(_line("Total"',
              '    out.append("-" * WIDTH)\n'
              '    if inv.discount_pct:\n'
              '        out.append(_line("Subtotal", inv.subtotal_cents()))\n'
              '        out.append(_line(f"Discount ({inv.discount_pct}%)", -inv.discount_cents()))\n'
              '    out.append(_line("Total"')
open(p, "w").write(s)
PY
cat > tests/test_discount.py <<'PY'
import unittest

from billing.invoice import Invoice, Item, render


class DiscountTest(unittest.TestCase):
    def test_rounds_half_up(self):
        inv = Invoice("D-1", [Item("Pen", 1, 433)], discount_pct=50)
        self.assertEqual(inv.total_cents(), 216)
        self.assertEqual(render(inv).splitlines()[-2], "Discount (50%)" + "-$2.17".rjust(26))

    def test_large_amounts_use_separators(self):
        inv = Invoice("D-2", [Item("Laptop", 10, 129999)], discount_pct=10)
        self.assertIn("-$1,299.99", render(inv))


if __name__ == "__main__":
    unittest.main()
PY
