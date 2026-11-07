"""Refunds for returned items."""
from . import money

RESTOCKING_PCT = 15


def refund_cents(item, qty_returned, opened=False):
    """Refund for returning qty_returned of an invoice item; opened goods pay a restocking fee."""
    gross = item.unit_cents * qty_returned
    fee = money.percent_of(gross, RESTOCKING_PCT) if opened else 0
    return gross - fee
