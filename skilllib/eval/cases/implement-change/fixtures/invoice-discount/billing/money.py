"""Money helpers. Amounts are integer cents everywhere; do money math and formatting through these."""
from decimal import ROUND_HALF_UP, Decimal


def percent_of(cents, pct):
    """pct percent of an amount in cents, rounded half-up to a whole cent (the ledger's rule)."""
    exact = Decimal(cents) * Decimal(str(pct)) / 100
    return int(exact.quantize(Decimal(1), rounding=ROUND_HALF_UP))


def fmt(cents):
    """Format cents for display: 1234567 -> '$12,345.67', -250 -> '-$2.50'."""
    sign = "-" if cents < 0 else ""
    dollars, rest = divmod(abs(cents), 100)
    return f"{sign}${dollars:,}.{rest:02d}"


def parse(text):
    """Parse a displayed amount back to cents: '$1,234.50' -> 123450, '-$2.50' -> -250."""
    t = text.strip().replace(",", "")
    neg = t.startswith("-")
    t = t.lstrip("-").lstrip("$")
    cents = int((Decimal(t) * 100).quantize(Decimal(1), rounding=ROUND_HALF_UP))
    return -cents if neg else cents
