---
name: performance
description: Use when code, a job, endpoint or query is too slow, burns CPU or memory, leaks, or needs a benchmark or speed guard. Measure, profile, fix the hot spot, re-measure. Not for finding the commit that slowed it (bisect-regression).
---

# Make it faster, with numbers

Find where the time or memory actually goes, fix that, and show before/after numbers with unchanged results.

## Fast path

If a profile already points at one hot spot and the fix is local, skip to step 5, but still save a baseline first
(step 2) and finish with the comparison (step 6). No speed claim without numbers.

## Steps

1. **Pick the workload.** The exact command and an input close to real size; generate one if needed. Small inputs
   hide quadratic costs: scale the input until one run takes at least about a second. Note what "fast enough" means
   if the user said.

2. **Save a baseline** (timing and output together):
   `python3 <skill folder>/scripts/bench.py -n 5 --save /tmp/perf-base.json -- <command>`
   It prints `RUNS … median=…` and `OUTPUT sha256=…`. Put the output in a file the command prints to stdout, or
   make it print a digest, so the comparison in step 6 covers the results.

3. **Profile; don't guess.** The user's suspicion and yours are hypotheses. Commands per runtime (Python cProfile,
   Node `--cpu-prof`, Go pprof, Rust/C perf, JVM JFR, Swift xctrace, SQL `EXPLAIN`, memory tools) are in
   `references/profilers.md`; for a Node `.cpuprofile`, run `python3 <skill folder>/scripts/cpuprofile_top.py FILE`.
   Read the profile two ways: by cumulative time (which call path is expensive) and by self time (which function
   burns it). Look at call counts: cheap work done once per item can still be the cost.

4. **Name the cause.** Typical, in order of payoff:
   - **Algorithmic**: membership or `index` on a list inside a loop, nested loops over the same data, sorting or
     copying inside a loop, string building with `+=`, one query per row (N+1).
   - **Repeated work**: recomputing, re-reading, re-parsing or re-compiling the same thing each iteration.
   - **I/O**: unbuffered writes, a commit or request per row, sync calls that could be batched.
   - **Memory**: unbounded caches or lists, references kept after use, whole files read instead of streamed.

5. **Fix the top item, one change at a time.** Keep behavior identical: order (a dict keeps insertion order, a set
   doesn't), tie-breaking, float summation order, handling of bad input, output format. Run the tests.

6. **Measure again against the baseline:**
   `python3 <skill folder>/scripts/bench.py -n 5 --compare /tmp/perf-base.json -- <command>`
   It prints `SPEEDUP` and `OUTPUT same` or `OUTPUT DIFFERENT` (exit 1). Different output means the change is
   wrong: fix or revert it. Profile again; stop when the target is met or the top remaining item is under ~10% of
   the time. Revert changes that didn't measurably help.

7. **Guard it when asked** (or when the project already has benchmarks): add a benchmark or test that compares
   ratios, not absolute milliseconds (machines differ). For example, time n and 4n items and fail if the ratio
   shows quadratic growth, or compare against a reference implementation in the same run with a generous margin.

## Rules

- **Don't** optimize what the profile doesn't show. A suspected regex, JSON or logging call is often cheap while a
  loop elsewhere is quadratic.
- **Don't** change results for speed (sampling, dropping order, approximations, caching without invalidation)
  unless the user asks; offer it as an option instead.
- **Don't** trust one run or a tiny input. Compare medians of several runs on the same machine, same input.
- **Don't** micro-optimize (local variable tricks, rewriting loops as comprehensions) before fixing complexity;
  the gain is noise next to an O(n²) term.
- Bound every cache you add (size or lifetime) and say what invalidates it.

## When no one can answer

Choose the workload yourself (from README, fixtures or a generator, scaled as in step 1) and state it. If the only
big win would change the output or an API, don't take it: report it as an option with its expected gain. Stop and
report if measuring needs production data or infrastructure you don't have.

## Done means

A report with: the **workload** (command, input size); **before and after** medians and the speedup (or memory
peak before/after); the **profile evidence** (top entries before, and after); **what changed** and why it is
faster (e.g. O(n·u) to O(n)); **output identical** (bench.py `OUTPUT same`, tests passing); remaining hot spots.
