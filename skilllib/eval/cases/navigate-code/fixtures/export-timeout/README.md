# exporter

Exports datasets to the warehouse and imports files back.

    python3 -m exporter.cli export orders
    python3 -m exporter.cli import data/returns.csv

Settings live in `settings.ini`, one section per command. Exports time out after 30 seconds by default
(`DEFAULT_TIMEOUT` in `exporter/config.py`).

Tests: `python3 -m unittest discover -s tests`
