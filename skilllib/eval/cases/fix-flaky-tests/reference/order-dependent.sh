# Reference fix: promotions work on a copy of the rates instead of mutating the shared cache.
python3 - <<'PY'
p = "shop/promotions.py"
s = open(p).read()
s = s.replace("    rates = get_rates()\n", "    rates = dict(get_rates())\n")
open(p, "w").write(s)
PY
