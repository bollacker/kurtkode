from .csvload import read_rows


def load_products(path):
    """Unit prices by SKU, from an export with columns sku,name,price."""
    return {r["sku"]: float(r["price"]) for r in read_rows(path)}
