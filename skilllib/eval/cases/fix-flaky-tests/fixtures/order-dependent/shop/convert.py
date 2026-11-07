from .rates import get_rates


def convert(amount_usd, currency):
    """An amount in USD expressed in another currency, rounded to cents."""
    return round(amount_usd * get_rates()[currency], 2)
