from .convert import convert


class Cart:
    def __init__(self, currency="USD"):
        self.currency = currency
        self.lines = []

    def add(self, name, price_usd, qty=1):
        self.lines.append((name, price_usd, qty))

    def total(self):
        return round(sum(convert(p, self.currency) * q for _, p, q in self.lines), 2)
