#!/usr/bin/env python3
"""tally: a small expense tracker for the command line.

Expenses and budgets are kept in ~/.tally/tally.db.
"""
import argparse
import datetime
import os
import re
import sqlite3
import sys

EXIT_OVER_BUDGET = 3


def db_path():
    return os.environ.get("TALLY_DB", "tally.db")


def connect():
    conn = sqlite3.connect(db_path())
    conn.execute("CREATE TABLE IF NOT EXISTS expenses (day TEXT, category TEXT, cents INTEGER, note TEXT)")
    conn.execute("CREATE TABLE IF NOT EXISTS budgets (category TEXT PRIMARY KEY, cents INTEGER)")
    return conn


def amount(text):
    """'12.50' or '12' -> 1250 (cents)."""
    if not re.fullmatch(r"\d+(\.\d{1,2})?", text):
        raise argparse.ArgumentTypeError(f"amount must look like 12 or 12.50, got {text!r}")
    whole, _, frac = text.partition(".")
    return int(whole) * 100 + int((frac + "00")[:2])


def day(text):
    try:
        return datetime.date.fromisoformat(text).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError(f"date must be YYYY-MM-DD, got {text!r}")


def money(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def this_month():
    return datetime.date.today().strftime("%Y-%m")


def month_totals(conn, month):
    rows = conn.execute("SELECT category, SUM(cents) FROM expenses WHERE day LIKE ? GROUP BY category"
                        " ORDER BY category", (month + "-%",))
    return dict(rows.fetchall())


def cmd_add(args, conn):
    when = args.date or datetime.date.today().isoformat()
    conn.execute("INSERT INTO expenses VALUES (?, ?, ?, ?)", (when, args.category, args.amount, args.note))
    conn.commit()
    print(f"added {money(args.amount)} to {args.category} on {when}")
    return 0


def cmd_report(args, conn):
    month = args.month or this_month()
    totals = month_totals(conn, month)
    if not totals:
        print(f"no expenses in {month}", file=sys.stderr)
        return 1
    for category, cents in totals.items():
        print(f"{category:<12} {money(cents):>10}")
    print(f"{'total':<12} {money(sum(totals.values())):>10}")
    return 0


def cmd_budget(args, conn):
    conn.execute("INSERT OR REPLACE INTO budgets VALUES (?, ?)", (args.category, args.amount))
    conn.commit()
    print(f"budget for {args.category}: {money(args.amount)} a month")
    return 0


def cmd_check(args, conn):
    totals = month_totals(conn, this_month())
    over = 0
    for category, limit in conn.execute("SELECT category, cents FROM budgets ORDER BY category").fetchall():
        spent = totals.get(category, 0)
        over += spent > limit
        print(f"{'OVER' if spent > limit else 'ok':<5} {category}: {money(spent)} of {money(limit)}")
    return EXIT_OVER_BUDGET if over else 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="tally", description="Track expenses and monthly budgets.")
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("add", help="record an expense")
    p.add_argument("amount", type=amount)
    p.add_argument("category")
    p.add_argument("--note", default="")
    p.add_argument("--date", type=day, help="YYYY-MM-DD (default: today)")
    p.set_defaults(func=cmd_add)
    p = sub.add_parser("report", help="totals per category for a month")
    p.add_argument("--month", help="YYYY-MM (default: this month)")
    p.set_defaults(func=cmd_report)
    p = sub.add_parser("budget", help="set a monthly budget for a category")
    p.add_argument("category")
    p.add_argument("amount", type=amount)
    p.set_defaults(func=cmd_budget)
    p = sub.add_parser("check", help="compare this month's spending with the budgets")
    p.set_defaults(func=cmd_check)
    args = ap.parse_args(argv)
    conn = connect()
    try:
        return args.func(args, conn)
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
