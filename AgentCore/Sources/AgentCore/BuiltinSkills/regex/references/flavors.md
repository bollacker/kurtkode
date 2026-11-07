# Regex flavors: what differs

Read this when the pattern will run somewhere other than Python or JavaScript, or a construct fails to compile.

| Feature | Python `re` | JavaScript | PCRE (PHP, `grep -P`, Perl) | Go / RE2 (also Rust `regex`) | POSIX ERE (`grep -E`, `awk`, `sed -E`) | sed BRE (`sed`, `grep`) |
|---|---|---|---|---|---|---|
| `\d` `\w` `\s` | yes (Unicode by default) | yes (ASCII `\d`) | yes | yes (ASCII) | no: `[0-9]` `[[:alnum:]_]` `[[:space:]]` | no |
| Non-greedy `*?` | yes | yes | yes | yes | no | no |
| Non-capturing `(?:…)` | yes | yes | yes | yes | no: use `(…)` | no |
| Named group | `(?P<n>…)` only | `(?<n>…)` | `(?<n>…)` or `(?P<n>…)` | `(?P<n>…)` (Go 1.22+ also `(?<n>…)`) | no | no |
| Lookahead / lookbehind | yes (lookbehind fixed width) | yes (lookbehind any width) | yes (fixed width) | **no** | no | no |
| Backreference `\1` | yes | yes | yes | **no** | in `grep -E` (GNU), not portable | yes |
| Groups, `+`, `?`, `{n}` | plain | plain | plain | plain | plain | `\(…\)`, `\+`, `\?`, `\{n\}` (GNU) |
| Anchors | `^ $`, `\A \Z` | `^ $` (`m` flag per line) | `^ $ \A \z` | `^ $ \A \z` | `^ $` | `^ $` |
| Inline flags `(?i)` | yes (at start) | no: flags after `/…/i` | yes | yes | no: `grep -i` | no: `I` modifier (GNU) |
| Full-string match | `re.fullmatch` | `^(?:…)$` | `^(?:…)$` or `\A…\z` | `^(?:…)$` | `grep -x` | `^…$` |
| Catastrophic backtracking | yes | yes | yes | no (linear time) | depends | depends |

Other differences that bite:

- `$` in Python matches before a final `\n`; use `\Z` (or `fullmatch`) to forbid it. JavaScript `$` without
  the `m` flag matches only at the very end.
- `.` does not match `\n` unless the `s` flag (Python `re.S`, JS `s`, Go `(?s)`) is on.
- `\b` is Unicode-aware in Python 3 `str` patterns, ASCII in JavaScript without the `u` flag.
- `grep` without `-E` uses BRE: `+`, `?`, `|`, `()` are literals unless escaped (GNU) — prefer `grep -E`.
- macOS (BSD) `sed` needs `sed -E` for ERE and `sed -i ''` for in-place; GNU `sed -r` is the same as `-E`.
- Inside a character class, `]` goes first and `-` goes first or last: `[]a-z-]`.
- In JavaScript regex literals escape `/`; in strings passed to `new RegExp("…")` double every backslash.
- Shell quoting: put the pattern in single quotes; a `'` inside needs `'\''`. Or keep it in a file
  (`grep -E -f pat.txt`, `regex_test.py --pattern-file`).
