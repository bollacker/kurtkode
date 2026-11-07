import csv, io


def to_csv(inv):
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["sku", "name", "stock", "value"])
    for i in inv.items.values():
        w.writerow([i.sku, i.name, i.stock, round(i.unit_cost * i.stock, 2)])
    return out.getvalue()
