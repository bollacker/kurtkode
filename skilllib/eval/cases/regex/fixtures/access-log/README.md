# logparse

Pulls request records out of the service log. Python 3, standard library only.

    python3 logparse.py samples/requests.log      # one JSON object per request line
    python3 -m unittest discover -s tests -t .

## Request lines

    <timestamp> <LEVEL> [api] <METHOD> <path> user=<user> status=<code> took=<duration> [key=value ...]

- timestamp: `2026-10-03T12:00:01Z` or `2026-10-03 12:00:01,250`, then one space
- LEVEL: `DEBUG`, `INFO`, `WARN` or `ERROR`, then one or more spaces
- component: only `[api]` lines are requests; the METHOD comes right after it
- METHOD: `GET`, `POST`, `PUT`, `PATCH` or `DELETE` (upper case)
- path: no spaces; may have a query string
- user: a bare name, or a double-quoted name that may contain spaces; `-` means anonymous
- status: three digits
- took: a number, optionally with decimals, followed by `ms` or `s`
- more `key=value` fields may follow `took`
- lines may end with `\r\n` or trailing spaces

`parse_line(line)` returns `{"method", "path", "user", "status", "ms"}` with `user` None for `-`, `status` an int
and `ms` the duration in milliseconds as a float, or None for any line that is not a request line.
