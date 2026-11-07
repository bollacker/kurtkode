# Reference: one re-entrant lock guards every read-modify-write of stock levels, and transfer holds it across both
# halves, so check-then-act is atomic and there is no lock ordering to get wrong.
python3 - <<'PY'
p = "depot/stock.py"
s = open(p).read()
s = s.replace('from . import audit\n', 'import threading\n\nfrom . import audit\n\n_lock = threading.RLock()  # guards every Warehouse.stock dict\n')
s = s.replace('''        have = self.stock.get(sku, 0)
        if have < qty:
            raise OutOfStock(f"{self.name}: {sku} has {have}, need {qty}")
        audit.record("reserve", warehouse=self.name, sku=sku, qty=qty, before=have)
        self.stock[sku] = have - qty''', '''        with _lock:
            have = self.stock.get(sku, 0)
            if have < qty:
                raise OutOfStock(f"{self.name}: {sku} has {have}, need {qty}")
            audit.record("reserve", warehouse=self.name, sku=sku, qty=qty, before=have)
            self.stock[sku] = have - qty''')
s = s.replace('''        have = self.stock.get(sku, 0)
        audit.record("restock", warehouse=self.name, sku=sku, qty=qty, before=have)
        self.stock[sku] = have + qty''', '''        with _lock:
            have = self.stock.get(sku, 0)
            audit.record("restock", warehouse=self.name, sku=sku, qty=qty, before=have)
            self.stock[sku] = have + qty''')
s = s.replace('''    src.reserve(sku, qty)
    dst.restock(sku, qty)''', '''    with _lock:
        src.reserve(sku, qty)
        dst.restock(sku, qty)''')
open(p, "w").write(s)
PY
grep -q "with _lock" depot/stock.py
