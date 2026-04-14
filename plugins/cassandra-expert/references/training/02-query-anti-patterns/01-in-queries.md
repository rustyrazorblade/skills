# Topic: IN() Queries

## Objective
Understand why large IN() queries are a sub-optimal scatter-gather, and replace them with concurrent async queries from the application.

## Why This Matters
IN() queries look like a convenient way to fetch multiple records in one call. Internally, Cassandra turns a partition-key IN() list into one lookup per value and assembles the results on a single coordinator — a sub-optimal scatter-gather. Firing the same queries concurrently from the application is faster, spreads coordinator load across the cluster, and limits the blast radius of any one failure.

---

## Concept

### What IN() Does Internally

```sql
SELECT * FROM users WHERE user_id IN (?, ?, ?, ?, ?);
```

Cassandra translates this into individual partition lookups — one per value. A single coordinator dispatches all of them and assembles the results. A 100-value IN() query is 100 separate lookups funnelled through one coordinator node — a sub-optimal scatter-gather.

### Why This Is Slower Than Concurrent Queries

If you fire 100 individual queries concurrently from your application, the scatter-gather is distributed: the driver picks a different coordinator per request, and the cluster as a whole does the work instead of one node. If any one request fails, only that request needs to be retried — the blast radius is tiny. With IN(), a single failure fails the whole query and every successful lookup inside it has to be redone.

### Async Pipelining: Process Results as They Arrive

The bigger win of concurrent async queries is **pipelining**. With IN(), the client blocks until the coordinator has assembled every row into one response — the request only completes when the slowest lookup completes, and nothing useful happens on the client until then. With a pipeline of async queries, each individual response lands at the client as soon as it's ready, and the application can start processing — transforming, writing out, rendering, forwarding downstream — while the remaining queries are still in flight.

Concretely: if 100 lookups each take 5ms, a blocking IN() gives you all 100 rows after ~500ms+ (plus coordinator assembly overhead), and 500ms of wall time where the client did nothing. An async pipeline at 50 in-flight concurrency gives you the first response in ~5ms, and by the time the last one lands you've already finished processing most of the earlier ones. For any workload where you're doing non-trivial work per row — serializing, writing to another system, streaming to a user — the end-to-end time is dramatically lower because the client spends less time blocked on large requests and more time making forward progress.

This is especially important for larger fan-outs. A thousand-key IN() with slow tails can stall the client for seconds; a thousand async queries with a bounded concurrency window (e.g., a semaphore of 50) let you keep the pipeline full and finish the work in roughly the time of the critical path plus overhead.

### When IN() on Clustering Columns Is OK

IN() on a **clustering column** (not partition key) within a single partition is fine — it's a single partition read with a filter applied. The concern is IN() on partition keys, which forces the coordinator to do the whole scatter-gather itself.

---

## Examples

### Anti-pattern: large IN() on partition key
```python
# ANTI-PATTERN: 100 lookups funnelled through one coordinator
user_ids = [...]  # 100 UUIDs
rows = session.execute(
    "SELECT * FROM users WHERE user_id IN %s",
    [user_ids]
)
```

### Correct: concurrent async queries (Python)
```python
from cassandra.concurrent import execute_concurrent_with_args

get_user = session.prepare("SELECT * FROM users WHERE user_id = ?")

def get_users(user_ids):
    results = execute_concurrent_with_args(
        session,
        get_user,
        [(uid,) for uid in user_ids],
        concurrency=50  # tune based on cluster capacity
    )
    return [row for success, rows in results if success for row in rows]
```

### Correct: concurrent async queries (Java)
```java
PreparedStatement getUser = session.prepare("SELECT * FROM users WHERE user_id = ?");

public List<Row> getUsers(List<UUID> userIds) {
    List<CompletableFuture<AsyncResultSet>> futures = userIds.stream()
        .map(id -> session.executeAsync(getUser.bind(id)).toCompletableFuture())
        .collect(Collectors.toList());

    return CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]))
        .thenApply(v -> futures.stream()
            .map(f -> f.join().one())
            .filter(Objects::nonNull)
            .collect(Collectors.toList()))
        .join();
}
```

### Correct: concurrent async queries (Go)
```go
func getUsers(ctx context.Context, session *gocql.Session, userIDs []gocql.UUID) ([]User, error) {
    results := make([]User, len(userIDs))
    g, ctx := errgroup.WithContext(ctx)

    sem := make(chan struct{}, 50) // limit concurrency

    for i, id := range userIDs {
        i, id := i, id
        g.Go(func() error {
            sem <- struct{}{}
            defer func() { <-sem }()

            var u User
            if err := session.Query(
                "SELECT user_id, name, email FROM users WHERE user_id = ?", id,
            ).WithContext(ctx).Scan(&u.ID, &u.Name, &u.Email); err != nil {
                return err
            }
            results[i] = u
            return nil
        })
    }
    return results, g.Wait()
}
```

---

## Pulse Check

> Your application needs to load profile data for 200 users to render a page. A teammate suggests:
> ```sql
> SELECT * FROM users WHERE user_id IN (?, ?, ?, ... 200 values);
> ```
>
> **Why is this slower than the alternative, and what should you do instead?**

*(Expected answer: IN() on the partition key funnels 200 lookups through a single coordinator — a sub-optimal scatter-gather. The alternative — 200 concurrent async queries — distributes the scatter-gather across the cluster and keeps any one failure's blast radius to a single lookup. Use `execute_concurrent_with_args` (Python), `executeAsync` + CompletableFuture (Java), or goroutines with a semaphore (Go). Limit concurrency to avoid overwhelming the cluster — 50 concurrent is a reasonable default.)*

---

## See Also

**In this session:**
- [ALLOW FILTERING](./02-allow-filtering.md)
- [Token Range Queries](./03-token-range-queries.md)
- [Excessive Async Operations](./11-excessive-async.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Drivers](../../general/drivers.md)
- [Thread Pools](../../general/thread-pools.md)
- [Prepared Statements](../../general/prepared-statements.md)
