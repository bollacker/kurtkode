"""Line pricing."""


def line_total(price_cents, qty):
    """Total for qty units, in cents."""
    if qty < 1:
        raise ValueError("qty must be at least 1")
    return price_cents * qty
