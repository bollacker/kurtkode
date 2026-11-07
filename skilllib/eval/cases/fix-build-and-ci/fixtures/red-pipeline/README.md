# invoicer

Invoice totals and currency conversion. Exchange rates are kept in `data/rates.csv` and compiled to
`build/rates.json` by `tools/build_rates.py`. CI runs `bash ci.sh` (lint, build, tests).
