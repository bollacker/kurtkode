"""Order totals."""
from parcel.shipping import shipping_cost


def order_total(items, zone):
    """items: list of (price, weight_g) pairs, weights in grams. Returns goods plus shipping, in dollars."""
    goods = sum(price for price, _ in items)
    weight_g = sum(w for _, w in items)
    return round(goods + shipping_cost(weight_g=weight_g, zone=zone), 2)
