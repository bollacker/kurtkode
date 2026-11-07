"""Stress scenarios for depot.stock, run by check.py in a subprocess (so a deadlock can be timed out).
Prints one line per problem; exit 0 when there are none."""
import sys, threading, time

sys.path.insert(0, ".")
sys.setswitchinterval(1e-6)  # switch threads as often as possible
from depot import audit, stock
from depot.stock import OutOfStock, Warehouse, transfer

_record = audit.record


def slow_record(event, **fields):  # widens the window between reading and writing a stock level
    _record(event, **fields)
    time.sleep(0.0002)


audit.record = slow_record
problems = []


def run_threads(n, fn):
    ts = [threading.Thread(target=fn, args=(i,), daemon=True) for i in range(n)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()


for rnd in range(3):
    audit.clear()
    # 1. Overselling: 200 attempts at 1 unit each for 60 units in stock.
    w = Warehouse("east", {"lamp": 60})
    ok = []

    def buyer(i):
        for _ in range(10):
            try:
                w.reserve("lamp", 1)
                ok.append(1)
            except OutOfStock:
                pass

    run_threads(20, buyer)
    if len(ok) != 60 or w.available("lamp") != 0:
        problems.append(f"round {rnd}: {len(ok)} reservations succeeded for 60 units, stock left {w.available('lamp')}")
    reserves = [e for e in audit.entries() if e["event"] == "reserve"]
    if len(reserves) != len(ok):
        problems.append(f"round {rnd}: {len(ok)} reservations but {len(reserves)} audited")

    # 2. Lost updates: concurrent restocks and reservations.
    w = Warehouse("west", {"desk": 500})
    taken = []

    def mixed(i):
        for _ in range(25):
            if i % 2:
                w.restock("desk", 2)
            else:
                try:
                    w.reserve("desk", 1)
                    taken.append(1)
                except OutOfStock:
                    pass

    run_threads(16, mixed)
    want = 500 + 8 * 25 * 2 - len(taken)
    if w.available("desk") != want:
        problems.append(f"round {rnd}: desk stock {w.available('desk')} after restocks and reservations, want {want}")

    # 3. Transfers both ways between two warehouses: units are conserved and nothing deadlocks.
    a, b = Warehouse("a", {"chair": 40}), Warehouse("b", {"chair": 40})

    def mover(i):
        src, dst = (a, b) if i % 2 else (b, a)
        for _ in range(40):
            try:
                transfer(src, dst, "chair", 1)
            except OutOfStock:
                pass
            if src.available("chair") < 0 or dst.available("chair") < 0:
                problems.append(f"round {rnd}: negative stock during transfers")

    run_threads(12, mover)
    total = a.available("chair") + b.available("chair")
    if total != 80:
        problems.append(f"round {rnd}: {total} chairs after transfers between a and b, want 80")

for p in dict.fromkeys(problems):
    print(p)
sys.exit(1 if problems else 0)
