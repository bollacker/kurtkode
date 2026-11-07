TAX_RATES = {"EU": 0.21, "UK": 0.20, "US": 0.0}


def tax_rate(customer):
    region = customer.region.upper()  # regions are typed by hand in the admin UI, case varies
    return TAX_RATES.get(region, 0.0)


def invoice_total(customer, lines):
    """Gross total for (quantity, unit price) lines, rounded to cents."""
    net = sum(qty * price for qty, price in lines)
    return round(net * (1 + tax_rate(customer)), 2)
