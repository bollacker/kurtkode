# Reference fix at the root cause: the shared CSV reader splits lines with splitlines(), so '\r\n' doesn't leave
# '\r' on the last field. invoice.py stays as it is.
python3 - <<'PY'
p = "store/csvload.py"
s = open(p).read()
s = s.replace('text.split("\\n")', "text.splitlines()")
open(p, "w").write(s)
PY
