---
name: concurrency
description: Use when code has races, lost updates, double-processing, deadlocks, data races or missing awaits, or must be made thread-safe or parallel. Reproduce, make it atomic, prove it. Not for flaky tests (fix-flaky-tests).
---

# Fix races, deadlocks and async bugs

Make every read-decide-write on shared state atomic, without deadlocks, and prove it under a stress test.

## Fast path

If the shared state and the unprotected read-modify-write are obvious and local (a counter, a check-then-insert),
put the whole sequence under one shared lock or an atomic operation. Still write the stress test (step 2) and run it
before and after.

## Steps

1. **Map the shared state.** List everything mutable that more than one thread, task or process can reach: globals,
   singletons, class attributes, caches, files, database rows. List every code path that reads or writes each one.
   Write the invariant that must hold ("stock never below 0; stock = start + restocked - reserved").

2. **Reproduce with a stress test before fixing.** Many workers start together (a barrier) and call the operations
   in loops; at the end assert the invariant. Widen the race window from the test, not the product code: patch a
   function called between the read and the write to sleep briefly, and in Python call `sys.setswitchinterval(1e-6)`.
   Run it 10+ times. Race detectors and stress tools per language are in `references/tools.md`
   (`go test -race`, ThreadSanitizer, Swift `-sanitize=thread`, jcstress, loom).

3. **Find each critical section:** a read, a decision or computation on it, and a write that depends on it
   (check-then-act, read-modify-write, lazy initialization, iterating while another path mutates). The whole
   sequence must be atomic, not only the write.

4. **Fix, simplest correct option first:**
   - **Remove the sharing**: per-worker state merged at the end, immutable data, or a queue with one owner.
   - **An atomic operation that exists**: SQL `UPDATE t SET n = n - ? WHERE id = ? AND n >= ?` and check the row
     count; `INSERT … ON CONFLICT`; `sync/atomic`, `AtomicInteger`, `std::atomic`.
   - **One lock** shared by every path that touches the state, held across the whole critical section. Start with
     one coarse lock; split it only if a measurement shows contention. Use a re-entrant lock if a locked method
     calls another locked method.
   - **Async code** (one thread, races at each `await`): don't decide on state read before an `await`; use
     `asyncio.Lock` or a mutex; await every promise or task (no fire-and-forget); `Promise.all`/`gather` for
     parallel work.
   - **Across processes or machines**: transactions with row locks (`SELECT … FOR UPDATE`), conditional updates,
     file locks, idempotency keys.

5. **Rule out deadlocks.** If any path holds two locks, every path must take them in one global order (sort by id or
   name), or use a single lock. Don't call callbacks, I/O or other modules' locked code while holding a lock. To
   diagnose a hang, take a thread dump (see `references/tools.md`) and look for two threads each waiting on a lock
   the other holds.

6. **Prove it.** The stress test passes 10+ runs in a row with the widened window; every test that could hang has
   a timeout so a deadlock fails instead of blocking; the existing tests pass.

## Rules

- **Don't** fix a race with sleeps, retries, timeouts or fewer threads. They make it rarer, not gone.
- **Don't** lock only the write. The read and the decision belong in the same critical section.
- **Don't** create the lock inside the function (`with threading.Lock():`, `new Mutex()` per call): each caller
  gets its own lock and nothing is excluded. The lock lives with the state it guards.
- **Don't** take two locks in different orders in different paths, or hold a lock while sleeping, doing network
  I/O or awaiting.
- **Don't** assume an operation is atomic because it is one line: `x += 1`, `d[k] = d.get(k, 0) + 1` and
  `if key not in cache: cache[key] = …` are not, GIL or not.

## When no one can answer

Choose the coarsest correct fix (one lock per piece of shared state, or the database's atomic update), and note
that finer locking is possible if contention shows up. Stop and report instead if correctness needs a protocol change
across services (distributed locks, idempotency keys in an API), with the race written out.

## Done means

A report with: the **shared state and invariant**; the **race** as an interleaving ("T1 reads 1, T2 reads 1, both
pass the check, both write 0"); the **fix** and why it is atomic and deadlock-free (which lock, lock order); the
**evidence**: stress test name and command, failures before (e.g. 10/10 runs) and after (0/10), and the suite result.
