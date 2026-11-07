"""Invoices and their plain-text rendering."""
from dataclasses import dataclass, field

from . import money

WIDTH = 40


@dataclass
class Item:
    description: str
    qty: int
    unit_cents: int

    def amount_cents(self):
        return self.qty * self.unit_cents


@dataclass
class Invoice:
    number: str
    items: list = field(default_factory=list)

    def subtotal_cents(self):
        return sum(i.amount_cents() for i in self.items)

    def total_cents(self):
        return self.subtotal_cents()


def _line(label, cents):
    amount = money.fmt(cents)
    return label + amount.rjust(WIDTH - len(label))


def render(inv):
    out = [f"Invoice {inv.number}", "-" * WIDTH]
    for i in inv.items:
        out.append(_line(f"{i.qty} x {i.description}", i.amount_cents()))
    out.append("-" * WIDTH)
    out.append(_line("Total", inv.total_cents()))
    return "\n".join(out)
