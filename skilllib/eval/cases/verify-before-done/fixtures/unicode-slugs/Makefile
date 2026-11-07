.PHONY: check unit integration

check: unit integration

unit:
	python3 -m unittest discover -s tests/unit -t .

integration:
	python3 -m unittest discover -s tests/integration -t tests/integration
