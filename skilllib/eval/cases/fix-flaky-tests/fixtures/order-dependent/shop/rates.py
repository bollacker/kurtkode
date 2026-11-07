"""Exchange rates against USD, loaded once per process."""
import json
import os

_RATES = None
_RATES_FILE = os.path.join(os.path.dirname(__file__), "rates.json")


def get_rates():
    """The current rates, read from rates.json on first use."""
    global _RATES
    if _RATES is None:
        with open(_RATES_FILE) as f:
            _RATES = json.load(f)
    return _RATES
