# Topic: Excessive Async Operations

## Objective
Understand why unbounded async concurrency overwhelms Cassandra, and how to limit it with a semaphore.

## Why This Matters
Async queries are essential for throughput — but "more async" is not always better. Firing thousands of concurrent queries at Cassandra saturates its thread pools, fills request queues, triggers timeouts, and causes cascading failures. Controlled concurrency — enough to keep Cassandra busy without overwhelming it — is the goal.

---

## Concept

### The Problem with Unbounded Concurrency

If you have 100,000 items to process and fire a Cassandra query for each one simultaneously:
- 100,000 requests hit the coordinators at once
- Coordinator queues fill up
- Requests start timing out
- Retries compound the load
- The cluster degrades for all users, not just this operation

Cassandra has finite thread pools. The `NativeTransportRequests` pool has a bounded size. Beyond that limit, requests queue — and if the queue fills, they're rejected. (Thread pools aren't covered in detail in the training itself — see the [Thread Pools](../../general/thread-pools.md) reference for the full list. For now, all you need to know: `NativeTransportRequests` is the pool that handles incoming CQL requests, and it's the first place to feel backpressure when you over-parallelize.)

### The Fix: Semaphore-Limited Concurrency

A semaphore limits how many queries are in flight at once. When the limit is reached, new queries wait until an in-flight one completes.

```
Semaphore limit: 50
In-flight: 50 queries → next query waits
One completes → next query fires
→ Always exactly 50 in flight, never more
```

### Choosing the Right Concurrency Limit

There's no universal answer — it depends on:
- Cluster size and thread pool configuration
- Query complexity (simple partition reads vs. large partition scans)
- Other traffic on the cluster

Start with 50-100 for bulk operations and tune based on observed latency and throughput. Monitor `nodetool tpstats` for the `NativeTransportRequests` pool — if it's saturated, reduce concurrency.

---

## Examples

### Anti-pattern: unbounded concurrency
```python
# ANTI-PATTERN: fires all queries simultaneously
async def process_all(items):
    tasks = [process_item(session, item) for item in items]  # 100,000 tasks
    await asyncio.gather(*tasks)  # all in flight at once
```

### Correct: cassandra-driver built-in (Python)
```python
from cassandra.concurrent import execute_concurrent_with_args

# concurrency parameter limits in-flight queries
results = execute_concurrent_with_args(
    session,
    insert_stmt,
    [(item.id, item.value) for item in items],
    concurrency=50,       # max 50 in-flight at once
    raise_on_first_error=False
)
```

### Correct: semaphore in Go
```go
func processAll(ctx context.Context, session *gocql.Session, items []Item) error {
    sem := make(chan struct{}, 50)  // semaphore: max 50 concurrent
    g, ctx := errgroup.WithContext(ctx)

    for _, item := range items {
        item := item
        g.Go(func() error {
            sem <- struct{}{}        // acquire
            defer func() { <-sem }() // release

            return session.Query(
                "INSERT INTO items (id, value) VALUES (?, ?)",
                item.ID, item.Value,
            ).WithContext(ctx).Exec()
        })
    }
    return g.Wait()
}
```

### Correct: semaphore in Java
```java
public void processAll(List<Item> items) throws InterruptedException {
    Semaphore sem = new Semaphore(50);
    List<CompletableFuture<Void>> futures = new ArrayList<>();

    for (Item item : items) {
        sem.acquire();
        CompletableFuture<Void> future = session
            .executeAsync(insertStmt.bind(item.getId(), item.getValue()))
            .toCompletableFuture()
            .thenRun(sem::release)
            .exceptionally(e -> { sem.release(); throw new RuntimeException(e); });
        futures.add(future);
    }
    CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
}
```

### Monitoring for saturation
```bash
# Check if Cassandra's request threads are saturated
nodetool tpstats
# Look for: NativeTransportRequests
# If "Pending" is consistently > 0, your concurrency is too high
# If "Pending" is always 0 and throughput is low, concurrency may be too low
```

---

## Pulse Check

> A data migration script needs to insert 500,000 records into Cassandra as fast as possible. A developer writes it to fire all 500,000 inserts asynchronously at once.
>
> **What will happen, and how should they rewrite it?**

*(Expected answer: Firing 500,000 concurrent requests will overwhelm Cassandra's coordinator thread pools. Request queues fill up, timeouts cascade, retries compound the load, and the cluster degrades for all other users. Rewrite with a semaphore limiting concurrency to 50-100 in-flight requests. Use `execute_concurrent_with_args` in Python (with `concurrency=50`), a channel-based semaphore in Go, or a Java `Semaphore`. The migration will complete nearly as fast — Cassandra will be kept at full utilization without being overwhelmed.)*

---

## See Also

**In this session:**
- [IN() Queries](./01-in-queries.md)
- [Synchronous (Blocking) Queries](./10-synchronous-queries.md)

**Reference:**
- [Thread Pools](../../general/thread-pools.md)
- [Dropped Messages](../../general/dropped-messages.md)
- [Drivers](../../general/drivers.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
