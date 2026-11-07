"""Name search for the catalog page."""
from shop.catalog import ITEMS, find_item


def search(term):
    """Items whose name contains term (case-insensitive), as (sku, name) pairs sorted by sku."""
    term = term.strip().lower()
    if not term:
        return []
    hits = []
    for sku in sorted(ITEMS):
        item = find_item(sku)
        if term in item["name"].lower():
            hits.append((sku, item["name"]))
    return hits


def lookup(sku):
    """The item's name, or None when the sku is unknown."""
    item = find_item(sku)
    return item["name"] if item else None
