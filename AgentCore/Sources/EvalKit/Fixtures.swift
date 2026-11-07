import AgentCore
import Foundation

/// Throwaway projects for scenarios, generated fresh for each trial so no run can see another's edits.
public enum Fixtures {
    static func write(_ root: URL, _ files: [String: String]) throws {
        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    /// git in `root` as the eval's identity, with signing and hooks off (a user's `commit.gpgsign` or global hooks would
    /// otherwise leave the fixture uncommitted); a failure throws, so a fixture that isn't what the task needs is a
    /// setup failure, not a run that every HEAD check misjudges.
    static func git(_ root: URL, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.name=eval", "-c", "user.email=eval@example.com", "-c", "commit.gpgsign=false",
                       "-c", "tag.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + args
        p.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        p.standardError = err
        try p.run()
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "Fixtures", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey:
                "git \(args.joined(separator: " ")) failed: " + String(decoding: data, as: UTF8.self).suffix(300)])
        }
    }

    /// The ref that marks a prepared fixture's commit, before the run. What a run changed is measured from it, so a run
    /// that commits its own work is still judged on that work (BUG_HUNT_2026-11-02.md item 43).
    static let baseRef = "refs/kurtkode/base"

    /// Marks `root`'s HEAD as the fixture's base (`baseRef`); nothing for a folder without git.
    static func markBase(_ root: URL) {
        _ = shell("git -C \(q(root.path)) update-ref \(baseRef) HEAD 2>/dev/null")
    }

    /// The fixture's commit before the run: `baseRef`, or HEAD for a run recorded before the ref existed.
    static func base(_ root: URL) -> String {
        shell("git -C \(q(root.path)) rev-parse -q --verify \(baseRef)").status == 0 ? baseRef : "HEAD"
    }

    /// Unpacks a `.tgz` fixture (a real repository snapshot without its `.git`) into `root`.
    static func untar(_ tgz: URL, into root: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-xzf", tgz.path, "-C", root.path]
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "Fixtures", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "tar failed on \(tgz.path)"])
        }
    }

    static func commitAll(_ root: URL) throws {
        try git(root, ["init", "-q"])
        try git(root, ["add", "-A"])
        try git(root, ["commit", "-qm", "fixture"])
    }

    // MARK: - Inventory service (explain-repo, find-definition)

    /// Line where `def reserve_stock` is declared in inventory/storage.py.
    public static let reserveStockLine = 31

    public static func inventory(at root: URL) throws {
        let storage = """
            \"\"\"SQLite-backed storage for items and reservations.\"\"\"
            import sqlite3

            from .models import Item, Reservation


            class InsufficientStock(Exception):
                \"\"\"Raised when a reservation asks for more units than are on hand.\"\"\"


            class SqliteStore:
                def __init__(self, path=":memory:"):
                    self.db = sqlite3.connect(path)
                    self.db.execute("create table if not exists items (sku text primary key, name text, quantity int)")
                    self.db.execute("create table if not exists reservations (id integer primary key, sku text, units int)")

                def add_item(self, item: Item):
                    self.db.execute("insert into items values (?, ?, ?)", (item.sku, item.name, item.quantity))

                def get_item(self, sku: str) -> Item:
                    row = self.db.execute("select sku, name, quantity from items where sku = ?", (sku,)).fetchone()
                    return Item(*row) if row else None

                def list_items(self):
                    return [Item(*r) for r in self.db.execute("select sku, name, quantity from items")]

                # Reservations hold stock for an order until it ships or is cancelled.
                # Callers must release() cancelled reservations.
                # Quantities are whole units.

                def reserve_stock(self, sku: str, units: int) -> Reservation:
                    item = self.get_item(sku)
                    if item is None or item.quantity < units:
                        raise InsufficientStock(f"{sku}: wanted {units}, have {item.quantity if item else 0}")
                    self.db.execute("update items set quantity = quantity - ? where sku = ?", (units, sku))
                    cur = self.db.execute("insert into reservations (sku, units) values (?, ?)", (sku, units))
                    return Reservation(cur.lastrowid, sku, units)

                def release(self, reservation: Reservation):
                    self.db.execute("update items set quantity = quantity + ? where sku = ?",
                                    (reservation.units, reservation.sku))
                    self.db.execute("delete from reservations where id = ?", (reservation.id,))
            """
        try write(root, [
            "README.md": "# Inventory service\n\nInternal tool.\n",
            "inventory/__init__.py": "",
            "inventory/models.py": """
                from dataclasses import dataclass


                @dataclass
                class Item:
                    sku: str
                    name: str
                    quantity: int


                @dataclass
                class Reservation:
                    id: int
                    sku: str
                    units: int
                """,
            "inventory/storage.py": storage,
            "inventory/pricing.py": """
                \"\"\"Prices with tax and volume discounts.\"\"\"

                TAX_RATE = 0.0825
                DISCOUNT_TABLE = [(100, 0.10), (20, 0.05)]


                def unit_discount(units: int) -> float:
                    for threshold, rate in DISCOUNT_TABLE:
                        if units >= threshold:
                            return rate
                    return 0.0


                def price_with_tax(unit_price: float, units: int) -> float:
                    subtotal = unit_price * units * (1 - unit_discount(units))
                    return round(subtotal * (1 + TAX_RATE), 2)
                """,
            "inventory/api.py": """
                \"\"\"HTTP handlers. Each takes a parsed request dict and returns (status, body).\"\"\"
                from .storage import InsufficientStock, SqliteStore
                from .pricing import price_with_tax

                store = SqliteStore("inventory.db")


                def list_items(request):
                    return 200, [vars(i) for i in store.list_items()]


                def reserve(request):
                    try:
                        r = store.reserve_stock(request["sku"], int(request["units"]))
                    except InsufficientStock as e:
                        return 409, {"error": str(e)}
                    return 201, {"reservation": r.id, "total": price_with_tax(request["unit_price"], r.units)}
                """,
            "cli.py": """
                \"\"\"Command line: python cli.py add|list|reserve ...\"\"\"
                import argparse

                from inventory.models import Item
                from inventory.storage import SqliteStore


                def main():
                    p = argparse.ArgumentParser()
                    sub = p.add_subparsers(dest="cmd")
                    add = sub.add_parser("add")
                    add.add_argument("sku"); add.add_argument("name"); add.add_argument("quantity", type=int)
                    sub.add_parser("list")
                    res = sub.add_parser("reserve")
                    res.add_argument("sku"); res.add_argument("units", type=int)
                    args = p.parse_args()
                    store = SqliteStore("inventory.db")
                    if args.cmd == "add":
                        store.add_item(Item(args.sku, args.name, args.quantity))
                    elif args.cmd == "list":
                        for item in store.list_items():
                            print(item)
                    elif args.cmd == "reserve":
                        print(store.reserve_stock(args.sku, args.units))


                if __name__ == "__main__":
                    main()
                """,
            "tests/test_storage.py": """
                import unittest

                from inventory.models import Item
                from inventory.storage import InsufficientStock, SqliteStore


                class StorageTests(unittest.TestCase):
                    def test_reserve_reduces_stock(self):
                        s = SqliteStore()
                        s.add_item(Item("A1", "Anvil", 5))
                        s.reserve_stock("A1", 2)
                        self.assertEqual(s.get_item("A1").quantity, 3)

                    def test_reserve_too_many(self):
                        s = SqliteStore()
                        s.add_item(Item("A1", "Anvil", 1))
                        with self.assertRaises(InsufficientStock):
                            s.reserve_stock("A1", 2)
                """,
        ])
        try commitAll(root)
    }

    // MARK: - Calculator with two bugs (fix-tests, deny-feedback)

    public static func calc(at root: URL) throws {
        try write(root, [
            "calc.py": """
                \"\"\"A tiny calculator library.\"\"\"


                def add(a, b):
                    return a + b


                def sub(a, b):
                    return a + b


                def mean(values):
                    \"\"\"Average of a non-empty list.\"\"\"
                    return sum(values) / (len(values) - 1)
                """,
            "test_calc.py": """
                import unittest

                from calc import add, mean, sub


                class CalcTests(unittest.TestCase):
                    def test_add(self):
                        self.assertEqual(add(2, 3), 5)

                    def test_sub(self):
                        self.assertEqual(sub(5, 3), 2)

                    def test_mean(self):
                        self.assertEqual(mean([2, 4, 6]), 4)


                if __name__ == "__main__":
                    unittest.main()
                """,
            "README.md": "# calc\n\nRun the tests with `python3 -m unittest -v`.\n",
        ])
        try commitAll(root)
    }

    // MARK: - Many files with unguessable facts (long-doc)

    static let words = ["Quillwort", "Marmoset", "Basalt", "Heron", "Tamarind", "Cobalt", "Juniper", "Osprey",
                        "Lichen", "Garnet", "Ibis", "Sorrel", "Tundra", "Walrus", "Yarrow", "Zircon", "Bramble",
                        "Kestrel", "Nettle", "Pumice", "Quokka", "Russet", "Sedge", "Vole"]

    /// `count` modules under src/, each declaring one class whose name can't be guessed from the file
    /// name, padded with enough code to cost real context. Returns path -> class name.
    public static func documentation(at root: URL, count: Int, seed: UInt64) throws -> [String: String] {
        var rng = SplitMix(seed: seed)
        var expected: [String: String] = [:]
        var files: [String: String] = ["README.md": "# Parts\n\nA collection of small modules.\n"]
        var used = Set<String>()
        for i in 1...count {
            var name: String
            repeat { name = words[Int(rng.next() % UInt64(words.count))] + String(10 + rng.next() % 90) } while used.contains(name)
            used.insert(name)
            let path = String(format: "src/part%02d.py", i)
            expected[path] = name
            var body = "\"\"\"Module \(i).\"\"\"\nimport math\n\n\n"
            for f in 0..<6 {
                body += "def helper_\(i)_\(f)(x, y=\(f + 1)):\n    \"\"\"Combine x and y (variant \(f)).\"\"\"\n"
                body += "    total = 0\n    for k in range(int(abs(x)) % 17 + 3):\n        total += math.sqrt(k + y) * \(f + 2)\n"
                body += "    return round(total, 3)\n\n\n"
            }
            body += "class \(name):\n    \"\"\"The part's main type.\"\"\"\n\n    def __init__(self, size=\(i)):\n        self.size = size\n\n"
            body += "    def weight(self):\n        return sum(helper_\(i)_\(0)(k) for k in range(self.size))\n"
            files[path] = body
        }
        try write(root, files)
        try commitAll(root)
        return expected
    }
}

/// Small deterministic RNG so fixtures are reproducible from a seed.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
