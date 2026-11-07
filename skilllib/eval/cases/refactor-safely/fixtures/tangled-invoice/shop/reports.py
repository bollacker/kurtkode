from .billing import compute_invoice


def monthly_revenue(orders):
    """Sum of invoice totals, rounded to cents."""
    return round(sum(compute_invoice(o)["total"] for o in orders), 2)
