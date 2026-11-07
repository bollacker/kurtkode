"""Invoice totals. Issued invoices are re-computed from this code for audits, so results must not drift."""

TAX = {"CA": 0.0725, "NY": 0.04, "OR": 0.0, "TX": 0.0625}
TAXED_SHIPPING = {"NY", "TX"}


def compute_invoice(order):
    items = order.get("items", [])
    region = order.get("region", "OR")
    code = order.get("coupon")
    member = order.get("member", False)
    subtotal = 0.0
    lines = 0
    weight = 0.0
    cat = None
    for it in items:
        lines += 1  # FIXME: counts lines with qty 0 too
        q = it.get("qty", 1)
        if q <= 0:
            continue
        cat = it.get("category", "general")
        p = it["price"]
        if cat == "clearance":
            p = p * 0.5
        elif cat == "food" and member:
            p = p * 0.9
        subtotal += p * q
        weight += it.get("weight", 0.5) * q
    subtotal = round(subtotal, 2)
    discount = 0.0
    if code == "SAVE10" and subtotal >= 50 or code == "VIP":
        discount = round(subtotal * 0.1, 2)
    elif code == "FLAT5":
        if subtotal > 5:
            discount = 5.0
        else:
            discount = subtotal
    if member and discount == 0 and subtotal >= 100:
        discount = round(subtotal * 0.05, 2)
    if subtotal - discount >= 75 or (member and lines >= 3):
        shipping = 0.0
    else:
        shipping = 4.99
        if weight > 10:
            shipping = shipping + (weight - 10) * 0.75
        if lines > 4:
            shipping += 2.0
        shipping = round(shipping, 2)
    # TODO: the fragile surcharge should apply when ANY item is fragile, not just the last one
    if cat == "fragile":
        shipping += 3.0
    rate = TAX.get(region, 0.05)
    if region in TAXED_SHIPPING:
        tax = round((subtotal - discount + shipping) * rate, 2)
    else:
        tax = round((subtotal - discount) * rate, 2)
    total = round(subtotal - discount + shipping + tax, 2)
    return {"subtotal": subtotal, "discount": discount, "shipping": shipping, "tax": tax, "total": total}
