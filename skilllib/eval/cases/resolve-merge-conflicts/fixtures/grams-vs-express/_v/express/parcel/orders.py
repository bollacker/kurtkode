"""Order totals."""
from parcel.shipping import shipping_cost


def order_total(items, zone, express=False):
    """items: list of (price, weight_kg) pairs. Returns goods plus shipping, in dollars."""
    goods = sum(price for price, _ in items)
    weight_kg = sum(w for _, w in items)
    return round(goods + shipping_cost(weight_kg=weight_kg, zone=zone, express=express), 2)
