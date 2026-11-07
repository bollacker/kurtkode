"""Line totals and invoice totals, in Decimal with cents rounding."""
from decimal import Decimal, ROUND_HALF_UP

CENT = Decimal("0.01")


def money(value):
    return Decimal(str(value)).quantize(CENT, rounding=ROUND_HALF_UP)


def line_total(qty, unit_price):
    return money(Decimal(qty) * money(unit_price))


def invoice_total(lines, discount_pct=0):
    """Sum of the line totals, less a percentage discount on the subtotal."""
    subtotal = sum((line_total(q, p) for q, p in lines), Decimal("0"))
    discounted = subtotal * (Decimal(100) - Decimal(discount_pct)) / Decimal(100)
    return money(subtotal)
