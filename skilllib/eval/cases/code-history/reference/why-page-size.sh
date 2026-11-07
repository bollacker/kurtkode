# Reference: follow the line past the restyle and the move to the commit that set 37, and quote its reason.
h=$(git log -L '/^PAGE_SIZE/,+1:billing/sync.py' --format='%H %s' | grep 'Cap Paywise' | cut -c1-10)
cat > HISTORY.md <<MD
commit: $h
reason: Paywise's /invoices endpoint silently drops every record after the 37th on a page (lost 212 invoices, INC-2291; Paywise ticket PW-88412, no fix date).
safe_to_raise: no

The value was set in $h ("Cap Paywise page size at 37", 2023-05-11). Later commits only moved the file
(paywise_sync.py -> billing/sync.py) and restyled the line; blame shows the restyle, not the reason.
tests/test_sync.py::test_page_size_within_limit guards the limit.
MD
