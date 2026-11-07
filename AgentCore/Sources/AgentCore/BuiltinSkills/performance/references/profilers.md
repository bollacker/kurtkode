# Profilers and measurement commands by runtime

Read the section for the project's runtime. All commands are non-interactive and print text. Tools marked
"(if installed)" are not always present: check with `command -v` and fall back to the first command.

## Python

```
python3 -m cProfile -s cumtime app.py ARGS 2>&1 | head -40          # call paths
python3 -m cProfile -o /tmp/prof.out -m package ARGS
python3 -c "import pstats; pstats.Stats('/tmp/prof.out').sort_stats('tottime').print_stats(15)"   # self time
python3 -c "import pstats; pstats.Stats('/tmp/prof.out').print_callers('index')"                   # who calls it
python3 -m timeit -s 'from mod import f; data = list(range(10**5))' 'f(data)'                      # one function
py-spy record -o /tmp/prof.svg -- python3 app.py      (if installed; also works on a running pid: py-spy dump --pid N)
```
`tottime` is self time, `cumtime` includes callees, `ncalls` shows per-item work. cProfile slows pure-Python code
about 2x evenly; it can hide time in C extensions, so confirm with timings.
Memory: `tracemalloc` snapshots around the suspect code:
```
import tracemalloc; tracemalloc.start(); ...; snap = tracemalloc.take_snapshot()
for s in snap.statistics("lineno")[:10]: print(s)
```
For growth over time, take two snapshots and print `snap2.compare_to(snap1, "lineno")[:10]`.

## Node.js

```
node --cpu-prof --cpu-prof-dir=/tmp/prof app.js ARGS
python3 <skill folder>/scripts/cpuprofile_top.py /tmp/prof/*.cpuprofile           # self time
python3 <skill folder>/scripts/cpuprofile_top.py --total /tmp/prof/*.cpuprofile   # inclusive
node --prof app.js && node --prof-process isolate-*.log | head -40                 # V8 tick profiler
```
Memory: `node --heap-prof app.js` (writes .heapprofile), `process.memoryUsage()` logged per iteration,
`node --trace-gc` for GC pressure. Benchmarks: `console.time` / `performance.now()` around the call, several runs.

## Go

```
go test -run '^$' -bench . -benchmem -cpuprofile /tmp/cpu.out ./pkg
go tool pprof -top -cum /tmp/cpu.out | head -30
go test -run '^$' -bench . -memprofile /tmp/mem.out ./pkg && go tool pprof -top -sample_index=alloc_space /tmp/mem.out
```
Services: import `net/http/pprof`, then `go tool pprof -top http://localhost:6060/debug/pprof/profile?seconds=20`.
Compare benchmark runs with `benchstat old.txt new.txt` (if installed).

## Rust, C, C++

Build optimized with symbols (`cargo build --release` with `debug = true` in `[profile.release]`; `-O2 -g`).
```
perf record -g ./target/release/app ARGS && perf report --stdio | head -60      (Linux)
valgrind --tool=callgrind ./app ARGS && callgrind_annotate callgrind.out.* | head -40
cargo flamegraph -- ARGS      (if installed)
sample <pid> 5 -file /tmp/sample.txt      (macOS, on a running process)
```
Memory: `valgrind --tool=massif`, `heaptrack` (if installed), `-fsanitize=address` for leaks in tests.

## JVM (Java, Kotlin)

```
java -XX:StartFlightRecording=duration=60s,filename=/tmp/rec.jfr -jar app.jar ARGS
jfr print --events jdk.ExecutionSample /tmp/rec.jfr | grep 'at ' | sort | uniq -c | sort -rn | head -20
jcmd <pid> GC.class_histogram | head -20      # what fills the heap
```
Benchmarks: JMH if the project has it; otherwise warm up before timing (the JIT).

## Swift and other native code on macOS

```
xcrun xctrace record --template 'Time Profiler' --output /tmp/t.trace --launch -- .build/release/app ARGS
xcrun xctrace export --input /tmp/t.trace --toc       # then export the time-profile table as XML
sample <pid> 5 -file /tmp/sample.txt                  # quickest: call tree of a running process
```
Build with `swift build -c release` before measuring; debug builds are often 10x slower and mislead.

## Databases

- SQLite: `EXPLAIN QUERY PLAN SELECT …` (look for `SCAN` on a big table where `SEARCH … USING INDEX` was expected).
- Postgres: `EXPLAIN (ANALYZE, BUFFERS) SELECT …`; compare estimated and actual rows.
- Count queries per request or job (log them); a count that grows with the data is N+1.

## Whole-process numbers

- Wall time and peak memory: `/usr/bin/time -l CMD` (macOS: "maximum resident set size" in bytes),
  `/usr/bin/time -v CMD` (Linux: "Maximum resident set size" in KB).
- Repeated timing with output check: `scripts/bench.py` in this skill; `hyperfine 'CMD'` (if installed).
