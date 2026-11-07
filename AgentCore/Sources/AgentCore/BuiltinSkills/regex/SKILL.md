---
name: regex
description: Use when writing, fixing or explaining a regular expression, or pulling fields out of log lines or text with one (grep, sed, validation). Tested on matching and non-matching examples. Not for renames across files (codemod).
---

# Write and test a regular expression

Build a pattern from examples of what must and must not match, and prove it on both before using it.

## Fast path

A short pattern for a simple shape (a number, a fixed prefix): write it anchored, run it through the script with
three lines that must match and three that must not, done.

## Steps

1. **Check that a regex is the right tool.** Use a real parser for JSON (`json`), CSV with quotes (`csv`),
   HTML/XML (`html.parser`, `xml.etree`), URLs (`urllib.parse`, `URL`), dates you must validate
   (`datetime.strptime`), anything nested. Regex fits line-shaped text, tokens and simple validation.

2. **Write the examples first, in files.**
   - `pos.txt`: real lines that must match (`grep` them from the actual data, not made up).
   - `neg.txt`: lines that must not, chosen to tempt the pattern: the right words in the wrong place (a
     request-looking string inside an error message, `user=` inside a URL query), near-miss formats, other
     components or levels, truncated lines.
   - Edge cases from the spec on both sides: optional parts present and absent, quoted values with spaces,
     both separators or timestamp forms, units, trailing spaces and `\r\n`, empty fields, non-ASCII text.
   - For extraction, `expect.jsonl`: `{"line": "...", "groups": {"user": "Bob Smith", "ms": "1.2"}}`, and
     `"groups": null` for lines that must not match.

3. **Know the flavor** that will run the pattern: Python `re`, JavaScript, PCRE, Go/RE2 (no backreferences or
   lookaround), POSIX ERE (`grep -E`, awk: no `\d`, no lazy `*?`), sed BRE (`\(` `\)` `\{` `\}`). Read
   `references/flavors.md` when the target is not Python or JavaScript, or a construct fails to compile.

4. **Write the pattern.**
   - Anchor it to the structure: `^…$` or `fullmatch` for whole lines and values; `re.match` or `^` when the
     record starts the line. Unanchored search is the main source of false matches.
   - Match the field, not "anything up to it": `[^"]*`, `\S+`, `\d+(?:\.\d+)?` instead of `.*` and `.*?`.
   - Alternatives for each allowed form: `(?:"(?P<q>[^"]*)"|(?P<bare>\S+))` for quoted or bare values.
   - Named groups; verbose mode (`re.X`) with a comment per part once it passes ~40 characters.
   - Escape literal `.` `?` `+` `*` `(` `)` `[` `]` `{` `}` `|` `^` `$` `\`; in Python use raw strings `r"…"`.
   - Avoid nested quantifiers over the same characters (`(a+)+`, `(.*,)*`): they backtrack exponentially on
     input that almost matches.

5. **Test it with the script and iterate until clean.**
   ```
   python3 <skill folder>/scripts/regex_test.py --pattern-file pat.txt \
       --match pos.txt --no-match neg.txt --expect expect.jsonl --mode search
   ```
   Use `--mode fullmatch` or `match` to match how the code will call it, `--engine node` for JavaScript, and
   `--pattern-file` to avoid shell quoting. MISS = should match and didn't; EXTRA = matched a negative; GROUPS =
   wrong capture. Exit 0 means every example passed.

6. **Test it where it lives.** Put the pattern in the code, convert captured strings there (numbers, units,
   "-" meaning none), and run the project's tests plus a count over real data:
   `grep -cE 'pattern' file` vs `wc -l`, or a short script that prints the lines that didn't parse.

## Rules

- **Don't** stop when the examples you were shown pass: add the negatives from step 2. A pattern that passes only
  the shown lines is usually unanchored or too loose.
- **Don't** use `.*` to skip to a field whose name can appear earlier in the line; match the structure in between.
- Don't hand-write a parser in regex for JSON, CSV, HTML or nested data.
- Keep the example files or turn them into unit tests, so the next change to the pattern is tested too.

## When no one can answer

If the spec doesn't say whether a borderline line should match, choose the stricter reading (reject), list the
borderline cases and your choice in the report or a code comment, and continue.

## Done means

- The pattern in the code, with a comment saying what it matches.
- The examples kept as tests (or example files next to the code).
- The script's `RESULT pass=N fail=0` line and the project's test result, quoted in the report.
