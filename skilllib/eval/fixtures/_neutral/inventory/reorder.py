def needs_reorder(inv):
    """SKUs at or below their reorder level, lowest stock first."""
    low = [i for i in inv.items.values() if i.stock <= i.reorder_level]
    return [i.sku for i in sorted(low, key=lambda i: i.stock)]
