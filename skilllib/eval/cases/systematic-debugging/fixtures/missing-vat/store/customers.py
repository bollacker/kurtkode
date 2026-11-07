from dataclasses import dataclass

from .csvload import read_rows


@dataclass
class Customer:
    code: str
    name: str
    email: str
    region: str


def load_customers(path):
    """Customers by code, from an export with columns code,name,email,region."""
    return {r["code"]: Customer(r["code"], r["name"], r["email"], r["region"]) for r in read_rows(path)}


def customers_in_region(customers, region):
    """Codes of the customers in a region, sorted (used for the regional mailing lists)."""
    return sorted(c.code for c in customers.values() if c.region == region)
