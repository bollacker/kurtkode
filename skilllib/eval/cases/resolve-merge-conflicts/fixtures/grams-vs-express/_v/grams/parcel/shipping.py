"""Shipping prices for parcels."""

RATES = {"domestic": 5.0, "intl": 15.0}  # flat part, dollars
PER_KG = 1.2  # dollars per kilogram


def shipping_cost(weight_g, zone):
    """Price in dollars for a parcel of weight_g grams sent to zone ("domestic" or "intl")."""
    return round(RATES[zone] + PER_KG * weight_g / 1000, 2)
