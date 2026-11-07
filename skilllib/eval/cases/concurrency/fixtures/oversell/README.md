# depot

Stock levels for the order service. Several order workers (threads) call `depot.stock` at the same time:
`Warehouse.reserve`, `Warehouse.restock` and `transfer`. Python 3, standard library only.
Tests: `python3 -m unittest`
