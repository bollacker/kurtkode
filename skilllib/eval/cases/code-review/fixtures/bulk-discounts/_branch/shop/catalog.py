"""Catalog lookup."""

ITEMS = {
    "A100": {"name": "Widget", "price_cents": 1250},
    "B200": {"name": "Gadget", "price_cents": 899},
    "C300": {"name": "Sprocket", "price_cents": 45},
}


def find_item(sku):
    """Return the item for sku, or None for an unknown sku."""
    return ITEMS.get(sku)
