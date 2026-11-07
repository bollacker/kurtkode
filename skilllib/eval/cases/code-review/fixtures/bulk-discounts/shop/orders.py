"""Order totals."""
from shop.catalog import find_item
from shop.pricing import line_total


def order_total(lines):
    """lines: list of (sku, qty). Returns (total_cents, unknown_skus); unknown skus are skipped."""
    total, unknown = 0, []
    for sku, qty in lines:
        try:
            item = find_item(sku)
        except KeyError:
            unknown.append(sku)
            continue
        total += line_total(item["price_cents"], qty)
    return total, unknown
