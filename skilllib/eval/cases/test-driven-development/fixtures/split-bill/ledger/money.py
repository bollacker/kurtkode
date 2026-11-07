"""Integer-cent money helpers."""


def parse_amount(text):
    """'12.34' -> 1234, '7' -> 700. Raises ValueError for anything else (more than 2 decimals, signs, blanks)."""
    s = text.strip()
    whole, _, frac = s.partition(".")
    if not whole.isdigit() or (frac and (not frac.isdigit() or len(frac) > 2)):
        raise ValueError(f"not an amount: {text!r}")
    return int(whole) * 100 + int(frac.ljust(2, "0") or 0)


def format_cents(cents):
    """1234 -> '$12.34', -5 -> '-$0.05'."""
    sign = "-" if cents < 0 else ""
    whole, frac = divmod(abs(cents), 100)
    return f"{sign}${whole}.{frac:02d}"
