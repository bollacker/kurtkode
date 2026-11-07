"""Command line tool: python3 cli.py --db shop.db <command> ..."""
import argparse
import sys

from accounts import db, orders, users


def main(argv=None):
    ap = argparse.ArgumentParser(prog="accounts")
    ap.add_argument("--db", default="shop.db")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("init")
    p = sub.add_parser("add-user")
    p.add_argument("email")
    p.add_argument("name")
    sub.add_parser("list-users")
    p = sub.add_parser("revenue")
    p.add_argument("month", help="YYYY-MM")
    a = ap.parse_args(argv)

    conn = db.connect(a.db)
    if a.cmd == "init":
        db.init_db(conn)
    elif a.cmd == "add-user":
        print(users.create_user(conn, a.email, a.name))
    elif a.cmd == "list-users":
        for u in users.list_users(conn):
            print(f"{u['id']}\t{u['email']}\t{u['name']}")
    elif a.cmd == "revenue":
        print(f"{orders.revenue(conn, a.month) / 100:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
