"""Shipping prices for parcels."""

RATES = {"domestic": 5.0, "intl": 15.0}  # flat part, dollars
PER_KG = 1.2  # dollars per kilogram
EXPRESS_FACTOR = 1.5  # express costs half as much again
EXPRESS_MIN_KG = 1.0  # express parcels are billed as at least 1 kg


def shipping_cost(weight_kg, zone, express=False):
    """Price in dollars for a parcel of weight_kg kilograms sent to zone ("domestic" or "intl").
    Express parcels are billed as at least EXPRESS_MIN_KG and cost EXPRESS_FACTOR times as much."""
    if express:
        weight_kg = max(weight_kg, EXPRESS_MIN_KG)
    cost = RATES[zone] + PER_KG * weight_kg
    if express:
        cost *= EXPRESS_FACTOR
    return round(cost, 2)
