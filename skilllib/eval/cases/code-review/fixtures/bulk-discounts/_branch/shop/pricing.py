"""Line pricing."""

# (minimum quantity, percent off), largest first.
BULK_TIERS = [(50, 10), (10, 5)]


def bulk_percent(qty):
    """Percent off for a line of qty units."""
    for min_qty, percent in BULK_TIERS:
        if qty > min_qty:
            return percent
    return 0


def line_total(price_cents, qty):
    """Total for qty units, in cents, after any bulk discount."""
    if qty < 1:
        raise ValueError("qty must be at least 1")
    gross = price_cents * qty
    discount = gross * bulk_percent(qty) // 100
    return gross - discount
