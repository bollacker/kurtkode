# Race detectors, stress tests and thread dumps by language

Read the section for the project's language when writing the stress test (step 2) or diagnosing a hang (step 5).

## Python

- Stress: `threading.Barrier(n)` so workers start together; `sys.setswitchinterval(1e-6)`; patch a function called
  inside the critical section to `time.sleep(0.0002)` (via `unittest.mock.patch`) to widen the window.
- Locks: `threading.Lock` / `RLock` (re-entrant) / `Condition`; `queue.Queue` for hand-off; `concurrent.futures`.
- Async: `asyncio.Lock`, `asyncio.gather`; run with `PYTHONASYNCIODEBUG=1` (or `asyncio.run(main(), debug=True)`)
  to see never-awaited coroutines and slow callbacks.
- Processes: `multiprocessing.Lock` / `Manager`; SQLite `BEGIN IMMEDIATE` to take the write lock before reading.
- Hang: `PYTHONFAULTHANDLER=1` then `kill -ABRT <pid>`, or `faulthandler.dump_traceback_later(30, exit=True)` in a
  test; `py-spy dump --pid <pid>` (if installed) shows every thread's stack.
- Free-threaded builds (3.13t+) have no GIL: races that were rare become common; same fixes apply.

## JavaScript / TypeScript (Node)

- One thread, but every `await` is a point where other requests run. Read-check-write across an `await` races.
- Lint for floating promises: `@typescript-eslint/no-floating-promises`, `no-misused-promises`.
- Stress: fire N calls with `Promise.all(Array.from({length: 50}, () => op()))` and check the invariant.
- Mutex: a promise-chain lock or the project's library (`async-mutex`); in the database, conditional updates.
- Workers (`worker_threads`) sharing memory: `Atomics` on `SharedArrayBuffer`.
- Hang: `node --inspect` is interactive; log `process._getActiveHandles()` or use `why-is-node-running` (if
  installed) to see what keeps the loop alive.

## Go

- `go test -race -count=20 ./...` (detector reports the two conflicting accesses with stacks).
- `sync.Mutex` / `RWMutex`, `sync/atomic`, channels with one owner goroutine; `sync.Once` for lazy init.
- `go vet` catches copied locks (`copylocks`).
- Hang: `kill -QUIT <pid>` or `GOTRACEBACK=all`; tests: `go test -timeout 60s` prints all goroutines on timeout.

## Rust

- Data races don't compile in safe Rust; logic races (check-then-act across two lock acquisitions) still happen.
- `cargo test` with `loom` for exhaustive interleavings (if the project uses it); `cargo +nightly miri test`.
- ThreadSanitizer: `RUSTFLAGS="-Zsanitizer=thread" cargo +nightly test --target <triple>`.
- Async: `tokio::sync::Mutex` across `.await`; `std::sync::Mutex` held across `.await` can deadlock.

## Java / Kotlin

- `synchronized`, `ReentrantLock`, `java.util.concurrent` (`ConcurrentHashMap.compute`, `AtomicLong`).
- `ConcurrentHashMap` makes single calls atomic, not `get` followed by `put`: use `compute`/`merge`.
- Stress: jcstress (if set up), or an `ExecutorService` with a `CountDownLatch` start gate.
- Hang: `jstack <pid>` reports "Found one Java-level deadlock" with both threads.

## Swift

- `-sanitize=thread` (`swift test --sanitize=thread`); strict concurrency checking (`-strict-concurrency=complete`).
- Actors serialize access, but state read before an `await` inside an actor may be stale after it (reentrancy).
- Hang: `sample <pid> 5`; `lldb -p <pid> --batch -o 'thread backtrace all'`.

## C / C++

- `-fsanitize=thread -g -O1` and run the tests; Helgrind (`valgrind --tool=helgrind`).
- `std::mutex` with `std::scoped_lock(a, b)` takes several locks without deadlock.
- Hang: `gdb -p <pid> -batch -ex 'thread apply all bt'`.

## Databases

- Lost update: two transactions read the same row, both write. Fix with a conditional `UPDATE … WHERE` plus a
  row-count check, `SELECT … FOR UPDATE` (Postgres/MySQL), or a version column (optimistic locking).
- Unique constraints plus `INSERT … ON CONFLICT DO NOTHING` beat check-then-insert.
- SQLite: one writer at a time; `BEGIN IMMEDIATE` avoids "database is locked" upgrades from read to write.
