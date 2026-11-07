# scratch notes

Task (issue #12): add a median to numstat: stats.median(), a --median flag, tests.

- [x] stats.median() first cut
- [x] tests for median
- [x] --median flag in cli.py
- [ ] get the median tests passing

## decisions
- 10/24 morning: for an even count, return the lower of the two middle values (like statistics.median_low).
  Simplest, and it always returns a value that is in the data.
- 10/24 afternoon: changed. Ops compare our numbers with the spreadsheet export, which averages the two
  middle values; they reported the mismatch on #12. So an even count returns the mean of the two middle
  values. Don't go back to median_low.
