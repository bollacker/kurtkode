"""Shipping options shown on the checkout page."""
from parcel.shipping import shipping_cost


def quick_quote(weight_kg, zone):
    """Both shipping options for one parcel, in dollars."""
    return {
        "standard": shipping_cost(weight_kg=weight_kg, zone=zone),
        "express": shipping_cost(weight_kg=weight_kg, zone=zone, express=True),
    }
