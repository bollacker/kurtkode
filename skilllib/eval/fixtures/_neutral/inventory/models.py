from dataclasses import dataclass, field


@dataclass
class Item:
    sku: str
    name: str
    unit_cost: float
    stock: int = 0
    reorder_level: int = 5
    tags: list = field(default_factory=list)


class Inventory:
    def __init__(self):
        self.items = {}

    def add(self, item):
        if item.sku in self.items:
            raise ValueError(f"duplicate sku {item.sku}")
        self.items[item.sku] = item

    def receive(self, sku, qty):
        self.items[sku].stock += qty

    def ship(self, sku, qty):
        item = self.items[sku]
        if qty > item.stock:
            raise ValueError("not enough stock")
        item.stock -= qty

    def value(self):
        return sum(i.unit_cost * i.stock for i in self.items.values())
