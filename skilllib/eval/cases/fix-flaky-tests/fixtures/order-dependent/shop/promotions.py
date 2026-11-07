from .rates import get_rates


def promo_rates(currency, percent_off):
    """Rates for a campaign that discounts prices in one currency by percent_off."""
    rates = get_rates()
    rates[currency] = round(rates[currency] * (100 - percent_off) / 100, 4)
    return rates


def campaign_price(amount_usd, currency, percent_off):
    rates = promo_rates(currency, percent_off)
    return round(amount_usd * rates[currency], 2)
