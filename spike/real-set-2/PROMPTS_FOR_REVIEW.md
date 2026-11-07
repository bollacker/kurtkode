# The real tasks after P2's set: prompts for review

Generated from each set's `tasks.json` (the source; edit there). Each prompt is what the model gets, and gold
checks the result with the commit's hidden tests (rdh, kk) or the facts listed (kkq). REAL_TASKS_PLAN.md,
"The first 11, built", has how they were checked.

## Set `kk`

### kk01: Append after a torn last line starts a new line

Commit `f684795`, kind fix, up to 60 steps.

> If a session file's last line was cut off (a crash mid-write), it still loads fine, because the torn line is skipped, but the next record appended is written onto the end of the torn line. That record is unreadable too and is lost along with it. We saw a model record disappear this way in the functional tests.
>
> For example: create a session in a SessionStore, append .message(.user("one")), then append the bytes `{"type":"message","message":{"id":"` to the end of the file with no newline. Loading gives messages ["one"]. Now, with a fresh store on the same folder, call load and then `append(.message(.user("two")), to: header.id)`. Reloading from another SessionStore should give ["one", "two"]; today "two" is missing.
>
> Fix `SessionStore.append(_:to:)` in AgentCore so that when the file does not end with a newline, the torn line is ended with one first, and the new record starts a line of its own. A file that already ends with a newline, and an empty file, get nothing extra. The wire log has the same flaw when it appends to its index.jsonl (WireLog in Debug/WireLog.swift); fix it the same way. When you're done, run the test suite and report what you changed and why.

### kk02: Edit permission rules miss apply_patch and file_path

Commit `2cbf82d`, kind fix, up to 60 steps.

> Permission rules of the form `Edit(<glob>)` only look at a tool call's "path" argument, so several ways of editing a file get past a deny rule. With a deny rule `Edit(secrets/**)`, `PermissionRules.decision(toolName:args:)` returns nothing for: `edit_file` called with "file_path" instead of "path"; `edit_file` called with "edits": [{"path": "secrets/key.txt", ...}]; and `apply_patch`, which names its files only inside the patch text (the "patch" argument, "*** Update File: ..." headers and the other forms the patch parser reads). A deny rule has to catch all of them.
>
> Make `Edit(...)` rules apply to apply_patch too, and resolve the paths a call names the way the tools themselves do (reuse the tools' own path and patch parsing rather than re-implementing it). A call that names several files, which only a patch does, is judged like this: a deny or ask rule matches if it covers any of the files, an allow rule only if it covers all of them. A call that names no path still matches no Edit rule, and the search tools (read_file, grep, glob, list_dir) with no path still count as searching the root, as now.
>
> With deny `Edit(secrets/**)` and allow `Edit(src/**)`: a patch touching src/a.swift and secrets/key.txt is denied; one touching src/a.swift and src/b.swift is allowed; one touching src/a.swift and README.md has no matching rule (nil). When you're done, run the test suite and report what you changed and why.

### kk03: Refusals and safety stops are declined replies

Commit `40b78d5`, kind edit, up to 60 steps.

> Today a refusal looks like a lost or empty reply, so the agent loop asks again (empty-reply nudge, open-todos nudge) or hands the turn to the fallback model, and the same refusal comes back. Add the notion of a declined reply.
>
> `TurnMeta` (ChatTypes.swift) gets `public var declined: Bool?`, set to true on the finished assistant message when the server or model declined: an Anthropic stop_reason "refusal", a Gemini finish reason in `GeminiStreamDecoder.declinedReasons` (a static Set<String>: BLOCKED, SAFETY, RECITATION, BLOCKLIST, PROHIBITED_CONTENT, SPII, IMAGE_SAFETY, IMAGE_PROHIBITED_CONTENT), or an OpenAI-style finish_reason "content_filter". For the last, `WireFormat.events(fromChunk:)` also emits the note "The server's content filter stopped the reply.". The decoders signal this with a new `StreamEvent.declined` case (Equatable), which TurnAccumulator turns into `declined`. The Anthropic refusal's existing note, e.g. ["The model declined to answer (cyber)."], stays.
>
> In `AgentLoop.run`, a declined reply is not nudged, is not retried on the fallback model, and ends the run as .completed with the reply kept: one request, nothing sent to the fallback. `AgentLoop.droppedCall(_:)` is false for a declined message.
>
> Also fix the lost-reply check in `droppedCall`: it should subtract the thinking the server billed, max(usage.reasoningTokens, reasoning text bytes / 4), from completionTokens (still a lost reply above 10 tokens left). A reply with 2,000 completion tokens, 1,995 of them reasoning tokens, a one-line reasoning summary and empty content is not lost; the same usage with reasoningTokens 0 is. When you're done, run the test suite and report what you changed and why.

### kk04: Pace requests by rate-limit headers; explain a 404

Commit `b1212ff`, kind edit, up to 60 steps.

> Parallel subagents on one Claude model share a rate-limit budget and collect 429s. Anthropic reports the budget on every response in `anthropic-ratelimit-*` headers; use them.
>
> Add `public actor RateLimits` in AgentCore/LLM (with `static let shared`, and a public `init()`) that keeps, per host, the windows for the limits "requests", "input-tokens" and "tokens". `record(host: String, headers: [AnyHashable: Any], now: Date = Date())` reads `anthropic-ratelimit-<name>-remaining` (an Int) and `anthropic-ratelimit-<name>-reset` (an ISO 8601 date, with or without fractional seconds) for each name that has both; header names are case-insensitive; a newer report for a limit replaces the older one, the other limits are kept. `pause(host: String, now: Date = Date()) -> TimeInterval` returns how long to wait before sending to that host: until the latest reset among windows that are used up and not yet reset (requests: 0 or fewer remaining; the token limits: under 1,000), at most 60 seconds, otherwise 0; an unknown host is 0. In ChatClient, wait that long before a request, and record each response's headers.
>
> Also `static func retryDelay(fromBody: Data) -> TimeInterval?` on RateLimits: Google's suggested wait in a 429 body (`"retryDelay": "23s"` -> 23), capped at 60, nil when absent. A retried transient failure without Retry-After uses it before the fixed backoff.
>
> A 404 turn error (retired or renamed model) should keep the server's message and add one that says the server doesn't offer the model: it must contain "The server doesn't offer <model>", then say to pick another model. When you're done, run the test suite and report what you changed and why.

### kk05: Hold OpenRouter price listings that jump more than 3x

Commit `ef71941`, kind edit, up to 60 steps.

> On 2026-10-26 OpenRouter's /models listed deepseek-v4-flash-0731 at 10x its price for a few hours, and 340 eval runs were costed at it. Make `RemotePrices` (LLM/CostEntry.swift) distrust a listed price that jumps.
>
> For remote (third-party) servers, remember the last price adopted for each model and hold a listing that is more than 3x above or below it. The decision is a static, pure function: `RemotePrices.steady(_ fresh: [String: PriceList.Price], remembered: inout [String: RemotePrices.Remembered], server: String, now: Date) -> (prices: [String: PriceList.Price], held: [String: String])`. `fresh` maps model to listed price; `remembered` is keyed "<server>|<model>"; the result's `prices` is `fresh` with each held model's remembered price put in place of the listed one, and `held` has a note containing the word "held" for each model whose listed price was not used.
>
> `RemotePrices.Remembered` (Codable, Sendable, Hashable) holds the adopted rates, per-search and per-request prices, when it was adopted, and `pending: PriceList.Rates?` plus when it was first seen. Rules: a model seen for the first time is adopted; a change of 3x or less (input and output both, each only compared when both are positive) is adopted at once and clears any pending price. A jump is held: the old price is used and the new one becomes pending. The pending price is adopted once a read at least 6 hours after it was first seen lists the same price again (within 1%). A different jump restarts the clock; a return to the old price adopts it and clears pending. Servers are kept apart.
>
> Keep `price(client:model:)` working, applying this for third-party servers only. Persist the memory as JSON at ~/Library/Caches/kurtkode/remote-prices.json via `RemotePrices(memory: URL?)`, `shared` using that default; the price's version string gets the held note appended after "; ". When you're done, run the test suite and report what you changed and why.

## Set `kkq`

### kkq01: What a project can configure, and what reads it

Commit `eb19878`, kind search, up to 60 steps.

> I want to document everything a project can put in its own folder to change how kurtkode behaves: instruction files, settings files, and the folders it looks in for extensions. Go through the code (the Swift package in AgentCore/) and list every file or folder inside a project, not in the user's home folder, that kurtkode reads to configure itself, including the alternative names it accepts for compatibility with other tools. For each one, say what it configures and which source file reads it, with a path:line reference. Also say which of them can make kurtkode run commands outside its sandbox, and what kurtkode does about that before running them. Don't change any files.

Facts the report must state:

- AGENTS.md instructions
- CLAUDE.md instructions
- settings.local.json
- permission rules from the settings files
- hooks from the settings files
- the test command (testCommand)
- MCP servers from .mcp.json
- skills folders
- subagent definitions
- slash commands
- prompt templates
- the user approves project hooks or servers first

### kkq02: When kurtkode offers to escalate a run

Commit `eb19878`, kind explain, up to 60 steps.

> Users ask when and why kurtkode offers to hand a request over to a stronger model. From the code (AgentCore/ and App/), explain: every reason a main run can earn an escalation offer, covering the automatic ones, the ones that depend on a setting, and the ones the user triggers; which ways a run can end that deliberately don't count; which model the offer goes to; and what the offer card's actions are, in what order. Give a path:line reference for each reason. Don't change any files.

Facts the report must state:

- the step limit
- a reply cut off at the output limit
- stuck repeating itself
- its last check failed after changing files
- the project's tests fail after the run
- a delegated task's check fails when re-run
- unfinished todos
- a review finds problems (a setting)
- the user's /escalate
- the user's thumbs down
- a cost limit doesn't count
- one tier up

### kkq03: How spending limits stop a run

Commit `eb19878`, kind explain, up to 60 steps.

> Explain how kurtkode keeps spending within the user's limits. From the code (AgentCore/ and App/): which spending limits exist and where the user sets each; what counts toward them, including subagents, summaries, local models, and remote models whose price kurtkode doesn't know; when the check happens; and what happens, and what the user can do, when a limit is reached. Give path:line references. Don't change any files.

Facts the report must state:

- a per-run limit
- a per-session limit
- a daily limit across sessions
- a project's daily limit
- unpriced remote models count at $3/$15 a million
- local models count nothing
- subagents count toward the same limits
- the run stops at the limit

## Sets `pkg` and `sqg` (public repositories, added 2026-10-30)

Hidden-test tasks from two public projects by other authors, commits after 2026-06-01 only: pypa/packaging (8) and
tobymao/sqlglot (4). The commit's tests are withheld and laid over the run's tree to grade it. Each prompt names the
interfaces and the strings the hidden tests check. These codebases are new to you, so what to look for is mostly: is
the request clear, and does it say too much about how to do it? Two commits say they were AI-assisted (pkg04, pkg06);
sqlglot commits tagged [CLAUDE] or [CODEX] were left out. In pkg04, pkg06, sqg01 and sqg03 the commit also changed old
tests that expected the old behavior, so those prompts ask for the old tests to be updated.

### pkg01: VersionRange.relation answers subset and disjointness together

pypa/packaging commit `78d8673`, kind edit, up to 60 steps.

> `packaging.ranges.VersionRange` answers `is_subset(other)` and `is_disjoint(other)` separately, so a caller that needs both walks the ranges twice. Add `VersionRange.relation(other)`, returning a member of a new enum `packaging.ranges.RangeRelation` (exported in the module's `__all__`) that answers both at once.
>
> `RangeRelation` has four members: `EMPTY` (self has no members), `SUBSET` (self has members and every one is in other), `DISJOINT` (self has members and none is in other) and `OVERLAPPING` (they share a member and self has one that other lacks). Each member has two read-only properties: `is_subset` (true for EMPTY and SUBSET) and `is_disjoint` (true for EMPTY and DISJOINT); assigning to either raises AttributeError. `repr(RangeRelation.SUBSET)` is `RangeRelation.SUBSET`.
>
> `relation(other)`'s flags always agree with `is_subset` and `is_disjoint`, that is with `(self & ~other).is_empty` and `(self & other).is_empty`, for any ranges: with `===` specifiers, and with prereleases None, True or False. As for the other set operations, both ranges must share the same configured pre-release policy, else ValueError. A range related to itself or to an equal range is SUBSET, or EMPTY if it is empty. Examples, writing a range by its specifiers: `>=1.5,<1.8` against `>=1.0,<2.0` is SUBSET and the reverse OVERLAPPING; `>=1.0,<2.0` against `>=3.0,<4.0` is DISJOINT; `>=1.0,<2.0` against `>=2.0,<3.0` is DISJOINT but `>=1.0,<=2.0` against it is OVERLAPPING; `>=1.0,<2.0,!=1.5` against `>=1.0,<2.0` is SUBSET and the reverse OVERLAPPING; an empty range (`>=2.0,<1.0`) is EMPTY against anything, and a non-empty range against an empty one is DISJOINT. For ranges decided by their bounds alone, get both answers from one pass over the bounds. Document the method and the enum in docs/ranges.rst. When you're done, run the test suite and report what you changed and why.

### pkg02: __replace__ for Specifier and SpecifierSet

pypa/packaging commit `ffced26`, kind edit, up to 60 steps.

> Make `packaging.specifiers.Specifier` and `SpecifierSet` work with `copy.replace()` (Python 3.13) by giving them a `__replace__` method.
>
> `Specifier.__replace__(*, operator=..., version=..., prereleases=...)`: keyword-only; an omitted argument keeps the current part; `prereleases=None` clears the explicit override, so pre-release handling is detected automatically again. It returns a new specifier, built as `f"{operator}{version}"` with that prereleases override and of the same class as self (subclasses are preserved), so a bad operator or version raises InvalidSpecifier. When nothing changes it returns self itself. The version of a `===` specifier can be replaced too: `Specifier("===anything").__replace__(version="else")` is `===else`.
>
> `SpecifierSet.__replace__(*, specifiers=..., prereleases=...)`: `specifiers` is a string or an iterable of `Specifier` (an iterator is fine); omitted keeps the current ones; `prereleases` as above; same class as self; a bad specifier raises InvalidSpecifier. It returns self when `specifiers` is omitted and the prereleases override doesn't change. For both, an unknown keyword raises TypeError (`copy.replace(s, unexpected="1")`).
>
> Example: `s = Specifier(">=1.0a1", prereleases=False)`; `s.__replace__(operator="<", version="2.0")` is `<2.0` with prereleases False, `s` is unchanged, and `s.__replace__(prereleases=None).prereleases` is True (detected from 1.0a1). `SpecifierSet(">=1.0a1,<2.0", prereleases=False).__replace__(specifiers=iter([Specifier("==2.0")]))` is `==2.0` with prereleases False. Document both in docs/specifiers.rst. When you're done, run the test suite and report what you changed and why.

### pkg03: SpecifierSet.is_subset, is_superset and is_disjoint

pypa/packaging commit `ba0188d`, kind edit, up to 60 steps.

> `SpecifierSet.to_range()` gives a `VersionRange`, which has `is_subset`, `is_superset` and `is_disjoint`. Add the same three relations to `packaging.specifiers.SpecifierSet` itself: `a.is_subset(b)` (every version matching a also matches b), `a.is_superset(b)` and `a.is_disjoint(b)` (no version matches both), each giving the same answer as on the sets' ranges.
>
> `other` must be a SpecifierSet: anything else, a string say, raises TypeError with a message that mentions SpecifierSet. If either set has a `===` specifier, raise ValueError with a message containing `===`. Two sets given different `prereleases` arguments (unset on one side counts as different) raise ValueError mentioning pre-release, as VersionRange already does. Examples: `>=3.12,<3.13` is a subset of `>=3.12` and of `>=3.11,<3.13` but not of `>=3.12,<3.12.5`; an unsatisfiable set such as `>=2.0,<1.0` is a subset of anything and disjoint from anything; the empty SpecifierSet `""` (every version) is not a subset of `>=3.12`; `<3.12` is disjoint from `>=3.12` but not from `>=3.11`. Document them in docs/specifiers.rst. When you're done, run the test suite and report what you changed and why.

### pkg04: Dependency-group errors: later siblings collected, each group once

pypa/packaging commit `959bb79`, kind fix, up to 60 steps.

> `packaging.dependency_groups.resolve_dependency_groups` (and `DependencyGroupResolver.resolve`) collect every problem in the groups they resolve and raise them together as an ExceptionGroup. Two cases are wrong.
>
> First, once one included group has failed to parse, problems in a later sibling include are no longer collected. With `root = [{"include-group": "bad"}, {"include-group": "wrapper"}]`, `bad = ["!!! bad invalid"]`, `wrapper = [{"include-group": "also-bad"}]` and `also-bad = ["!!! also invalid"]`, resolving root should raise two errors, the one for `!!! bad invalid` first and then the one for `!!! also invalid`.
>
> Second, a failing group is reported once for every path that reaches it. With `root` including `group1` and `group2`, both of which include `err = ["invalid requirement"]`, resolving root should raise one error, not two. Within one resolve call, report each failing group once. A group that failed must still not be cached as resolved, so a later call reports it again. Update the existing tests that this change breaks. When you're done, run the test suite and report what you changed and why.

### pkg05: Pylock.select rejects undeclared extras and dependency groups

pypa/packaging commit `23669b1`, kind edit, up to 60 steps.

> `Pylock.select(extras=..., dependency_groups=...)` in `packaging.pylock` silently accepts extras and dependency groups that the lock file doesn't declare. Make it raise `PylockSelectError` instead: `Undeclared extras: x3, x4` for requested extras missing from the lock's `extras`, and `Undeclared dependency groups: g3, g4` for requested groups found in neither `dependency_groups` nor `default_groups` (the names sorted and joined with ", "). Names are compared normalized (`canonicalize_name`), so a requested `X1` matches a declared `x1` and `DG1` a default group `dg1`, and the normalized names are the ones used for the selection. The error may surface when the result is iterated, as in `list(pylock.select(...))`. When you're done, run the test suite and report what you changed and why.

### pkg06: Metadata.from_email reports all its errors at once

pypa/packaging commit `2068340`, kind fix, up to 60 steps.

> `Metadata.from_email(data, validate=True)` in `packaging.metadata` reports problems in two rounds. If any header couldn't be parsed (an unknown field, or a single-value field such as Name given twice), it raises an ExceptionGroup with only those; the validation errors that `from_raw` would report (missing required fields, an invalid version) appear only after they are fixed.
>
> Collect both into one ExceptionGroup whose message is `invalid or unparsed metadata`: one InvalidMetadata per unparsed header (with today's messages) plus every error `from_raw` reports. A required field already reported as unparsed (Name given twice, so absent from the raw data) must not be reported a second time as missing. The raised group's `__context__` must be None, so don't raise it from inside an except block. Valid metadata is still returned as before.
>
> Examples: `Metadata-Version: 2.6\nName: packaging\nName: packaging-copy\nVersion: invalid version\n` gives exactly two errors, for the fields name and version; an empty string gives errors for metadata-version, name and version, under the message above; valid metadata with an extra `Unknown-Field: value` gives a single error for unknown-field. Update the existing tests that expect the old two-round behavior. When you're done, run the test suite and report what you changed and why.

### pkg07: parse_tag limit for compressed tag sets

pypa/packaging commit `4c362e3`, kind edit, up to 60 steps.

> Add a `limit` keyword to `packaging.tags.parse_tag`: `parse_tag(tag, *, validate_order=False, limit=None)`. A compressed tag such as `py2.py3-none-any` expands to the product of its dot-separated parts. When `limit` is given and that count exceeds it, raise a new `packaging.tags.TooManyTagsError` (a ValueError subclass, exported in the module's `__all__`) with the message `Compressed tag set would generate N tags, exceeding limit L`, before generating them. The count is taken before duplicates collapse: `py3.py3-none-any` counts 2. A count equal to the limit is allowed. A negative limit raises ValueError("limit must be non-negative"). `limit=None` keeps today's behavior, and `validate_order` works as before alongside it. Document the parameter and the exception in docs/tags.rst and add a CHANGELOG.rst entry. When you're done, run the test suite and report what you changed and why.

### pkg08: Post-release boundaries in SpecifierSet ranges

pypa/packaging commit `e7f0351`, kind fix, up to 60 steps.

> PEP 440 says `>V` excludes every post-release of V (unless V is itself a post-release). A single `Specifier(">1.0")` gets this right, but a SpecifierSet gets it wrong when another of its specifiers puts a boundary at a post-release of the same V: `SpecifierSet(">1.0,!=1.0.post1").contains("1.0.post2", prereleases=True)` is True, although `>1.0` rejects 1.0.post2, and `SpecifierSet(">1.0,<=1.0.post1").is_unsatisfiable()` is False, although no version can match.
>
> Fix the range logic SpecifierSet uses (src/packaging/_ranges.py) so that a set's membership always equals the conjunction of its specifiers' memberships, `filter` agrees (`SpecifierSet(">1.0,!=1.0.post1")` keeps only 1.1 of 1.0.post2, 1.0.post3 and 1.1), and `>V,<=V.postN` is unsatisfiable. This must also hold with epochs (`>1!1.0,!=1!1.0.post1` rejects 1!1.0.post2) and for development releases of post-releases (`1.0.post2.dev3`). When you're done, run the test suite and report what you changed and why.

### sqg01: BigQuery: transpile Trino date parts, FROM_BASE, APPROX_PERCENTILE, ARRAY_SORT and ARRAY_DISTINCT

tobymao/sqlglot commit `d17c768`, kind edit, up to 60 steps.

> Several Trino (and DuckDB/Spark) functions don't transpile to BigQuery. Fix the BigQuery generator (sqlglot/generators/bigquery.py) so that, reading Trino and writing BigQuery:
>
> 1. Date parts become EXTRACT: `YEAR(x)`, `MONTH(x)`, `QUARTER(x)`, `HOUR(x)`, `DAY(x)` and `DAY_OF_MONTH(x)` become `EXTRACT(<part> FROM x)` with parts YEAR, MONTH, QUARTER, HOUR, DAY, DAY; `DAY_OF_YEAR(x)` becomes `EXTRACT(DAYOFYEAR FROM x)` and `WEEK_OF_YEAR(x)` `EXTRACT(ISOWEEK FROM x)`. Trino's day_of_week is Monday=1..Sunday=7 and BigQuery's DAYOFWEEK Sunday=1..Saturday=7, so `DAY_OF_WEEK(x) * 2` becomes `(MOD(EXTRACT(DAYOFWEEK FROM x) + 5, 7) + 1) * 2`.
> 2. `FROM_BASE(s, 16)` becomes `CAST(REGEXP_REPLACE(s, '^([+-]?)', '\\10x') AS INT64)` (the sign kept before a 0x prefix); e.g. `FROM_BASE('-ff', 16)` gives `CAST(REGEXP_REPLACE('-ff', '^([+-]?)', '\\10x') AS INT64)`. Any other base is left as `FROM_BASE(s, 2)` with the warning `FROM_BASE is only supported for base 16`.
> 3. `APPROX_PERCENTILE(col, q)` with a literal quantile q between 0 and 1 and at most 5 decimal places becomes `APPROX_QUANTILES(col, n)[k]` with q = k/n in lowest terms (APPROX_QUANTILES takes at most 100,000 buckets): `APPROX_PERCENTILE(col, 0.95)` is `APPROX_QUANTILES(col, 20)[19]`, `APPROX_PERCENTILE(col, 0.00001)` is `APPROX_QUANTILES(col, 100000)[1]`, and the four-argument form with weight 1, `APPROX_PERCENTILE(col, 1, 0.5, 0.001)`, is `APPROX_QUANTILES(col, 2)[1]` (none of these may warn at unsupported_level RAISE). A weight other than 1, or a quantile that isn't such a literal (q, -0.5, 1.5, 0.000001, 1e-1000000, 1e1000000000, 0.50000000000000000000000000001), is generated as BigQuery's APPROX_QUANTILE with the arguments kept, e.g. `APPROX_QUANTILE(col, 0.5, 0.01, 2)`, and the warning `APPROX_QUANTILE needs a literal quantile and no weight`.
> 4. BigQuery can't sort an aggregate's result, so a sort or de-duplication of an ARRAY_AGG folds into it: Trino `ARRAY_SORT(ARRAY_AGG(x))` becomes `ARRAY_AGG(x ORDER BY x IS NULL, x)`; DuckDB `LIST_SORT(LIST(x), 'ASC', 'NULLS FIRST')` `ARRAY_AGG(x ORDER BY x)`, `ARRAY_REVERSE_SORT(LIST(x))` `ARRAY_AGG(x ORDER BY x DESC)`, `LIST_SORT(LIST(x), 'DESC', 'NULLS FIRST')` `ARRAY_AGG(x ORDER BY x IS NULL DESC, x DESC)`, `LIST_SORT(LIST(DISTINCT x), 'ASC', 'NULLS FIRST')` `ARRAY_AGG(DISTINCT x ORDER BY x)`; Trino `ARRAY_DISTINCT(ARRAY_AGG(x))` `ARRAY_AGG(DISTINCT x)`. Where a DISTINCT aggregate can't honor the requested NULL placement (`ARRAY_SORT(ARRAY_AGG(DISTINCT x))`, `ARRAY_SORT(ARRAY_DISTINCT(ARRAY_AGG(x)))`, DuckDB `LIST_SORT(LIST(DISTINCT x), 'DESC', 'NULLS FIRST')`) it still folds, to `ARRAY_AGG(DISTINCT x ORDER BY x)` or `... ORDER BY x DESC)`, with the warning `ARRAY_AGG(DISTINCT) only puts NULLs first when ascending`. What can't fold is left as it is, with the warning `ARRAY_SORT is only supported on an ARRAY_AGG without ORDER BY or LIMIT and with a literal order` (`ARRAY_DISTINCT ...` for ARRAY_DISTINCT): an ARRAY_AGG with ORDER BY or LIMIT, a lambda comparator, a non-aggregate argument (`ARRAY_SORT(x)`, `ARRAY_DISTINCT(x)`), or Spark's `SORT_ARRAY(COLLECT_LIST(x), y)` with a non-literal order (`ARRAY_SORT(ARRAY_AGG(x) FILTER(WHERE x IS NOT NULL))`).
> 5. DECIMAL beyond NUMERIC's range (29 integer digits, 9 fractional) becomes BIGNUMERIC: `DECIMAL(30, 0)`, `DECIMAL(20, 10)` and `DECIMAL(38)` are BIGNUMERIC, `DECIMAL(29, 0)` is NUMERIC, and a non-literal precision or scale (`DECIMAL(p, 0)`, `DECIMAL(38, s)`) stays NUMERIC.
>
> The test helper `_validate_array_sort` in tests/dialects/test_dialect.py takes an expected value or an (sql, warning) pair. Update the existing tests that expect the old BigQuery output for these functions. When you're done, run the test suite and report what you changed and why.

### sqg02: Oracle CREATE TABLE physical attributes and STORAGE

tobymao/sqlglot commit `5b949bd`, kind fix, up to 60 steps.

> Oracle's CREATE TABLE takes physical attributes and a STORAGE clause after the column list, or before AS SELECT, e.g. `CREATE TABLE t (id NUMBER) TABLESPACE ts PCTFREE 10 STORAGE (INITIAL 64K)`. sqlglot's Oracle dialect doesn't parse them. Add them:
>
> - `PCTFREE n`, `PCTUSED n`, `INITRANS n`, `MAXTRANS n`, `LOGGING` and `NOLOGGING`, in any order and mixed with `TABLESPACE name`, each parse to a new property expression `exp.PhysicalProperty`: the keyword, upper-cased, is its `this` (so `.name == "PCTFREE"`) and the number its `value` (`exp.Literal.number(10)`); LOGGING and NOLOGGING have no value. A keyword that needs a number and has none is a ParseError.
> - `STORAGE (...)` parses to a new `exp.StorageProperty` whose `expressions` are its options, each a PhysicalProperty named by the option with its `value`. Options: INITIAL, NEXT, MINEXTENTS, MAXEXTENTS, MAXSIZE, PCTINCREASE, FREELISTS, FREELIST GROUPS, BUFFER_POOL (KEEP, RECYCLE or DEFAULT), FLASH_CACHE and CELL_FLASH_CACHE (KEEP, NONE or DEFAULT). MAXEXTENTS and MAXSIZE also take UNLIMITED. INITIAL, NEXT and MAXSIZE take a size suffix (K, M, G, T, P, E), the value then being `exp.var("64K")`; `storage (initial 64 k next 1 m)` is written back as `STORAGE (INITIAL 64K NEXT 1M)`. ParseErrors: `STORAGE ()`, `STORAGE (INITIAL)`, `STORAGE (FREELIST 1)`, an unclosed `STORAGE (INITIAL 64K`, and an unknown option `STORAGE (INITIAL 64K UNKNOWN 1)`.
> - Both round-trip in Oracle after the schema, upper-cased (`create table t (id number) pctfree 10 nologging` is `CREATE TABLE t (id NUMBER) PCTFREE 10 NOLOGGING`), with identify=True quoting, before AS SELECT (`CREATE TABLE t PCTFREE 10 NOLOGGING AS SELECT 1 AS id FROM dual`), and pretty-printed one per line (`CREATE TABLE t (\n  id NUMBER\n)\nPCTFREE 10\nSTORAGE (INITIAL 64K NEXT 1M)\nLOGGING`). The parsed CREATE keeps its Schema of ColumnDefs.
> - Other dialects don't support them: generating for postgres with `unsupported_level=ErrorLevel.RAISE` raises UnsupportedError naming the property (physicalproperty, storageproperty). When you're done, run the test suite and report what you changed and why.

### sqg03: replace_placeholders keeps a replacement's grouping

tobymao/sqlglot commit `ad8764a`, kind fix, up to 60 steps.

> `sqlglot.expressions.replace_placeholders` substitutes expressions for placeholders (`:x` or `?`) in a parsed tree, but it drops the grouping a replacement needs: replacing `:x` in `:x * 2` with `a + b` prints `a + b * 2`, and a query can print bare, e.g. `SELECT * FROM :x` with `SELECT 1` gives `SELECT * FROM SELECT 1`. Fix it, as the expression builders do:
>
> - A replacement that is an operation (a binary operator, BETWEEN, IN, NOT, unary minus, bitwise NOT, AT TIME ZONE) is wrapped in parentheses when its placeholder is an operator's operand: `:x * 2` with `a + b` is `(a + b) * 2`; `NOT :x` with `a = 1 OR b = 2` is `NOT (a = 1 OR b = 2)`; `-:x` and `~:x` with `a + b` are `-(a + b)` and `~(a + b)`; `? - c` and `c - ?` with `a - b` are `(a - b) - c` and `c - (a - b)`; `:x[1]` with `a + b` is `(a + b)[1]`; `:x AT TIME ZONE 'UTC'` with `a + b` is `(a + b) AT TIME ZONE 'UTC'`; `:x BETWEEN 1 AND 2` with `a OR b` is `(a OR b) BETWEEN 1 AND 2`; `c = :x` with `a IN (1, 2)` is `c = (a IN (1, 2))`. Elsewhere nothing is added: `SELECT :x AS y`, a function argument (`ABS(:x)`, `COALESCE(:x, 1)`), an IN list item, `(:x) * 2`, a bare `:x`; and a column path, function call or plain identifier is never wrapped (`a.b.c.d.e * 2`, `ABS(a) * 2`, `a[1]`).
> - A replacement that is a query becomes a subquery (`exp.Subquery`) unless its slot takes a query: `SELECT * FROM :x` is `SELECT * FROM (SELECT 1)`, `:x + 1` is `(SELECT 1) + 1`, `SELECT :x AS y` is `SELECT (SELECT 1) AS y`, `COALESCE(:x, 1)` is `COALESCE((SELECT 1), 1)`, `x IN (:x, 3)` is `x IN ((SELECT 1), 3)`, `:x IN (1)` is `(SELECT 1) IN (1)`. Slots that take a query keep it bare: a bare `:x`, `(:x)`, a CTE body, a set-operation side (`:x UNION SELECT 2`), `CREATE TABLE t AS :x`, a single-argument function (`EXISTS(:x)`, `ANY(:x)`, `ALL(:x)`), and the single item of IN (`x IN :x` and `x IN (:x)` are `x IN (SELECT 1)`). A table, VALUES, ordered column, NULL or interval replacement is used as it is.
>
> Snowflake's NORMAL() is transpiled to DuckDB through placeholders, so its DuckDB output gains the grouping too: `... * COS(2 * PI() * ((ABS(HASH(42 + 1)) % 1000000) / 1000000.0)))`; update tests/dialects/test_snowflake.py accordingly. When you're done, run the test suite and report what you changed and why.

### sqg04: MySQL ALTER TABLE with actions and options in any order

tobymao/sqlglot commit `1a0fc42`, kind fix, up to 60 steps.

> A MySQL `ALTER TABLE` may mix actions and table options in any order, separated by commas: `ALTER TABLE t ADD c INT, AUTO_INCREMENT=5, ADD d INT`. sqlglot's parser (for dialects with `ALTER_TABLE_MIXED_ACTIONS`) only handles the options after all the actions, so a table option between two actions isn't parsed as one. Make the generic ALTER parser (sqlglot/parser.py) accept actions and table options interleaved in any order: that statement parses to an `exp.Alter` with two actions in `args["actions"]` and one option in `args["options"]`, none of them a Command, and is generated as `ALTER TABLE t ADD COLUMN c INT, ADD COLUMN d INT, AUTO_INCREMENT=5`. Statements that already parse keep their output. A statement with a part it can't parse still falls back to a Command with a warning, as now: MySQL `ALTER TABLE t ADD COLUMN c INT SECONDARY_ENGINE_ATTRIBUTE='{}', ADD COLUMN z INT` and StarRocks `ALTER TABLE t ADD COLUMN c INT TO r1, ADD COLUMN d INT` round-trip unchanged as commands. When you're done, run the test suite and report what you changed and why.

## Go sets `cel` and `opa` (2026-11-02)

Graded by the commit's hidden tests (`_test.go` and testdata files) inside the sandbox; cel-go runs `go test ./...`, OPA
`run-tests.sh` (its core packages, with the tests that need a port or DNS skipped). REAL_TASKS_PLAN.md, "A second
language from another author", has how they were built and checked.

### Set `cel`

#### cel01: Constant folding of `x in [x]` with NaN

google/cel-go commit `af38f75`, kind fix, up to 60 steps.

> cel-go's constant-folding optimizer (cel/folding.go, used through `NewConstantFoldingOptimizer`) rewrites `x in [..., x, ...]` to `true` when the identifier being looked for also appears in the list. That isn't sound when the identifier can hold a NaN double, because NaN isn't equal to itself: with `d` declared as a double and bound to NaN, the optimized `d in [d]` evaluates to true, while the unoptimized expression evaluates to false.
>
> Make the identifier match apply only when the identifier's declared type guarantees a value equal to itself: bool, bytes, duration, int, null, string, timestamp, type and uint, and lists and maps whose type parameters are all such types (for example list(int), list(list(int)), map(string, int)). For a double, dyn, a list or map that can hold a double or dyn, an optional type or a message type, leave the expression as it is. A literal needle still folds by CEL equality as before (`1 in [1, 2]` and `1.0 in [d, 1.0]` both become `true`). Update the existing cases in cel/folding_test.go that expect the old folding (`x in [1, 2, x]` with `x` a dyn no longer folds to `true`). When you're done, run the test suite and report what you changed and why.

#### cel02: Strict RFC 3339 in timestamp()

google/cel-go commit `41d9149`, kind fix, up to 60 steps.

> Converting a string to a timestamp in cel-go (`timestamp('...')` in CEL, `String.ConvertToType(TimestampType)` in common/types) goes through Go's `time.Parse` with `time.RFC3339`, which accepts strings that RFC 3339 forbids: a comma as the fractional separator (`2025-01-17T01:00:00,001Z`), a one-digit hour or minute (`2025-01-17T1:00:00Z`, `2025-01-17T01:5:00Z`), and out-of-range offsets (`+24:01`, `+00:60`).
>
> Make the conversion reject such strings with the error `invalid RFC 3339 timestamp "<input>"` (the input quoted as Go's `%q` quotes it), and keep accepting valid ones, such as `2025-01-01T12:34:56Z`, `2025-01-01T12:34:56.123456789Z`, a lowercase `t` or `z`, a leap second (`23:59:60`), and offsets like `+05:30`, `-08:00` and `+14:00`. The conversion is on a hot path, so keep it cheap. When you're done, run the test suite and report what you changed and why.

#### cel03: Depth limit for ASTs loaded from protos

google/cel-go commit `be9dacd`, kind edit, up to 60 steps.

> ASTs loaded through `cel.ParsedExprToAst`, `cel.CheckedExprToAst` or `cel.CheckedExprToAstWithSource` skip the parser's recursion limit (250), so a deeply nested AST built from a proto can exhaust the Go stack in `env.Check` or `env.Program` and crash the process. Add a depth check:
>
> 1. In common/ast, add `func ExceedsDepth(a *AST, maxDepth int) bool`. The root expression has depth 0; it returns true when some expression's depth is at least `maxDepth` (so `'a' == 'b'`, of depth 1, exceeds 1 but not 2). It returns false for a nil or empty AST and when `maxDepth` is zero or negative. Its own traversal must stay bounded, never going more than `maxDepth`+1 levels down, so it's safe on the deep inputs it guards against.
> 2. ASTs loaded through those cel helpers are checked against 250, the parser's default. `ParsedExprToAst` and `CheckedExprToAst` have no error return, so the problem is reported later: `env.Check` and `env.Program` on such an AST return an error that mentions `maximum expression nesting depth`, without recursing into it. `CheckedExprToAstWithSource` returns that error directly. ASTs built straight through the common/ast package aren't checked.
> 3. Add an environment option `cel.ExpressionNestingDepthLimit(limit int) EnvOption` that records the limit in the environment's configuration under the limit name `cel.limit.max_ast_depth`, so `env.ToConfig` exports it. When you're done, run the test suite and report what you changed and why.

#### cel04: Bound lists.range()

google/cel-go commit `13cff33`, kind fix, up to 60 steps.

> In cel-go's lists extension (ext/lists.go), `lists.range(n)` allocates n elements with no upper bound, so `lists.range(2147483647)` tries to allocate about 16 GB and crashes the process; it also accepts a negative n.
>
> Make `lists.range` return an evaluation error for a negative n and for an n above a maximum size, by default 1,000,000 (`lists.range(1000000)` is still allowed). Add a `ListsMaxRangeSize(size int64) ListsOption` to set the maximum; zero turns the limit off. When you're done, run the test suite and report what you changed and why.

#### cel05: Logical folding keeps non-bool operands

google/cel-go commit `0175dbb`, kind fix, up to 60 steps.

> cel-go's constant-folding optimizer (cel/folding.go) drops a literal operand of `&&` and `||`: `true && x`, `x && true`, `false || x` and `x || false` all become `x`. That's only right when `x` is a bool. For an operand of type dyn, the folded expression can evaluate to something that isn't a bool, where the original would have been an error.
>
> Only drop the literal when the other operand's type is bool. With `b` declared as bool, `true && b`, `b && true`, `false || b` and `b || false` still fold to `b`. With `x` declared as dyn, those forms stay as written, and so do longer chains such as `true && x && true && x` and `false || x || false || x`. Update the existing cases in cel/folding_test.go that expect the old folding. When you're done, run the test suite and report what you changed and why.

### Set `opa`

#### opa01: Mixed rule kinds on disjoint ref heads

open-policy-agent/opa commit `f6e3d5d0`, kind fix, up to 60 steps.

> In OPA, a single-value rule and a multi-value rule whose refs share a ground prefix and a variable, but differ in a later ground key, are rejected as conflicting:
>
> ```rego
> package play
>
> x := "node"
> obj[x].y := "foo"
> obj[x].z contains "bar"
> ```
>
> fails with `rego_type_error: conflicting rules data.play.obj[__local1__].z found`, although `y` and `z` can never be the same path. Make the compiler (v1/ast) accept single- and multi-value rules at the same node when their refs can't overlap, that is when some position holds a different ground term in each. Where they can overlap it must still report the conflict: `obj[x].y := "foo" if x := "node"` together with `obj[x].y contains "bar" if x := "node"` is still `conflicting rules`. When you're done, run the test suite and report what you changed and why.

#### opa02: Partial eval panic on a negated `every`

open-policy-agent/opa commit `01eefbab`, kind fix, up to 60 steps.

> OPA's partial evaluation panics with `interface {} is *ast.Every, not *ast.Term` when a query negates a rule whose body holds an `every` over unknown input:
>
> ```rego
> package test
>
> p if { not blocked }
>
> blocked if {
> 	every x in input.xs {
> 		x == 1
> 	}
> }
> ```
>
> Partially evaluating `data.test.p = true` with `input` unknown crashes. Fix it in v1/topdown: a negated expression that can't be negated trivially, an `every` among them, is saved in a support rule instead of being inlined. For the example, the residual query is `not data.partial.__not1_0_2__`, with the support module
>
> ```rego
> package partial
>
> __not1_0_2__ = true if {
> 	every __local0__3, __local1__3 in input.xs {
> 		__local1__3 = 1
> 	}
> }
> ``` When you're done, run the test suite and report what you changed and why.

#### opa03: net.cidr_contains on IPv6 subnets ending at ::ffff:ffff:ffff

open-policy-agent/opa commit `85b62162`, kind fix, up to 60 steps.

> OPA's `net.cidr_contains(A, B)` (v1/topdown/cidr.go) gives false negatives for the IPv6 subnets that end at `::ffff:ffff:ffff`, `::/80` through `::fffe:0:0/95`: `net.cidr_contains("::/80", "::/80")`, `net.cidr_contains("::/0", "::/80")` and `net.cidr_contains("::/79", "::/80")` are all false. It checks that A contains B's first and last address, and here B's last address falls in the IPv4-mapped block `::ffff:0:0/96`, which Go's `net.IPNet.Contains` turns into a 4-byte IPv4 address that then doesn't match A's IPv6 network.
>
> Make containment correct for every IPv6 CIDR pair, including those subnets. Don't break the mixed-family cases: `::/0` must still not contain a plain IPv4 address such as `1.2.3.4`, and single IPs and IPv4-mapped ranges keep working as before. The YAML cases under v1/test/cases/testdata/*/netcidrcontains are run by v1/topdown's tests. When you're done, run the test suite and report what you changed and why.

#### opa04: Reject some-in bindings that appear in the domain

open-policy-agent/opa commit `63f54da4`, kind fix, up to 60 steps.

> In OPA, `some i, x in xs[i]` compiles, because the compiler rewrites the domain after the binding, so `i` in the domain refers to the variable being declared. Make it a compile error, `var <name> assigned before`, at the `some` statement's location (for example `test.rego:4: rego_compile_error: var i assigned before`), when a variable that `some ... in` binds also appears in its domain. That covers the key (`some i, x in [[0]][i]`, also after an earlier `some i` or `i := 0`), the value (`some x in [[0]][x]`), and a variable inside a ref in the pattern (`some [input.xs[j], y] in input.ys[j]` reports `j`). These must keep compiling: `b contains y if { some [input.x, y] in input.arr }`, `b contains v if { some {k: v} in input.objs[k] }` and `f(xs) := y if { some [xs[0], y] in xs }`. When you're done, run the test suite and report what you changed and why.

#### opa05: Strict SemVer in semver.is_valid and semver.compare

open-policy-agent/opa commit `ae4ed955`, kind fix, up to 60 steps.

> OPA's SemVer parser (internal/semver, behind the `semver.is_valid` and `semver.compare` built-ins) accepts strings that SemVer 2.0.0 forbids: `semver.is_valid("01.2.3")` and `semver.is_valid("1.02.3")` (leading zeroes), `semver.is_valid("1.2.3-01")` (a leading zero in a numeric pre-release identifier), `semver.is_valid("1.2.3-")` and `semver.is_valid("1.2.3+")` (an empty pre-release or build section) are all true, and `semver.compare("1.02.3", "1.2.3")` returns 0.
>
> Make parsing reject leading zeroes in major, minor and patch, a leading zero in a numeric pre-release identifier, and an empty pre-release or build section after `-` or `+`. Build-metadata identifiers may keep leading zeroes, as the spec allows. `semver.is_valid` then returns false for these, and `semver.compare` errors on them the way it already does for an invalid version such as `1.2`. Add a CHANGELOG.md entry. When you're done, run the test suite and report what you changed and why.

#### opa06: Sibling leaves of a general ref aren't recursive

open-policy-agent/opa commit `23745504`, kind fix, up to 60 steps.

> In OPA, rules with a variable in their ref are stored at the node for their ground prefix, so sibling leaves such as `p[x].foo.bar` and `p[x].foo.baz` look like dependencies of each other, and this module is rejected as recursive:
>
> ```rego
> package test
>
> p[x].foo.bar if {
> 	x := "a"
> 	not p[x].foo.baz
> }
>
> p[x].foo.baz if {
> 	x := "a"
> 	false
> }
> ```
>
> Make the compiler's recursion check (v1/ast) tell siblings apart: sibling leaves and sibling subtrees under a variable aren't recursive. A leaf that depends on itself, on an ancestor, or on a dynamic position that could be itself, and mutual recursion across leaves, must still be reported, as `rule data.test.p[x].foo.bar is recursive: data.test.p[x].foo.bar -> data.test.p[x].foo.bar`, with a head variable under its source name (`data.test.q[x]`, not a generated `__local__` name).
>
> The planner (internal/planner, used for Wasm and IR) plans one function per ground path prefix, so with this change a rule that refers back into its own prefix would recurse there until the stack overflows. Make the planner report it instead, as `reference to data.test.p is not supported: rules sharing that path prefix are planned as a single function`, for the module above, for `p[x] := 1 if { x := "a" }` with `p.b := y if { y := p.a + 1 }`, and when the sibling is reached through a `with` function mock. Add a CHANGELOG.md entry. When you're done, run the test suite and report what you changed and why.
