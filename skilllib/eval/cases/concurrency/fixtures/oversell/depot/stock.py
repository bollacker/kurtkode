"""Stock levels per warehouse. Order workers call these from several threads."""
from . import audit


class OutOfStock(Exception):
    pass


class Warehouse:
    def __init__(self, name, stock=None):
        self.name = name
        self.stock = dict(stock or {})

    def available(self, sku):
        return self.stock.get(sku, 0)

    def reserve(self, sku, qty):
        """Take qty units of sku out of stock for an order. Raises OutOfStock if there aren't enough."""
        have = self.stock.get(sku, 0)
        if have < qty:
            raise OutOfStock(f"{self.name}: {sku} has {have}, need {qty}")
        audit.record("reserve", warehouse=self.name, sku=sku, qty=qty, before=have)
        self.stock[sku] = have - qty

    def restock(self, sku, qty):
        """Add qty units of sku (deliveries, cancelled orders)."""
        have = self.stock.get(sku, 0)
        audit.record("restock", warehouse=self.name, sku=sku, qty=qty, before=have)
        self.stock[sku] = have + qty


def transfer(src, dst, sku, qty):
    """Move qty units of sku from one warehouse to another; raises OutOfStock (and moves nothing) if src is short."""
    src.reserve(sku, qty)
    dst.restock(sku, qty)
