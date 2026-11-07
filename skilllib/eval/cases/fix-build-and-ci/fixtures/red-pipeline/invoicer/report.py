"""Plain-text invoice in the customer's currency."""
from invoicer.pricing import invoice_total, money, line_total
from invoicer.rates import load_rates


def convert(amount_usd, currency):
    return money(amount_usd * money(load_rates()[currency]))


def render(lines, currency="USD", discount_pct=0):
    out = [f"{qty} x {price} = {line_total(qty, price)}" for qty, price in lines]
    total = convert(invoice_total(lines, discount_pct), currency)
    out.append(f"TOTAL {total} {currency}")
    return "\n".join(out)
