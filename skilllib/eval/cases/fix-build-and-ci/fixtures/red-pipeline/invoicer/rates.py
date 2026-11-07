"""Exchange rates compiled by tools/build_rates.py."""
import json, os, warnings

RATES_FILE = os.path.join(os.path.dirname(__file__), "..", "build", "rates.json")


def load_rates(path=RATES_FILE):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        warnings.warn(f"{path} not found, only USD is available", RuntimeWarning)
        return {"USD": 1.0}
