# Topic: Synchronous (Blocking) Queries

## Objective
Understand why blocking on Cassandra queries in a request handler kills throughput, and replace synchronous patterns with async.

## Why This Matters
Cassandra queries typically complete in 1-5ms. If your application thread blocks waiting for each response, you can only handle as many concurrent requests as you have threads. Modern async patterns let a single thread handle hundreds of in-flight Cassandra requests simultaneously, multiplying throughput without multiplying thread count.

---

## Concept

### The Blocking Problem

In a synchronous model, each request handler thread blocks while waiting for Cassandra:

```
Thread 1: → send query → [blocked 2ms] → process result → respond
Thread 2: → send query → [blocked 2ms] → process result → respond
Thread 3: → send query → [blocked 2ms] → process result → respond
```

If you have 100 threads and each blocks for 2ms per query, your throughput ceiling is roughly:
```
100 threads / 0.002 sec = 50,000 requests/sec (theoretical max)
```

In practice, thread overhead, GC, and context switching reduce this further.

### The Async Advantage

In an async model, a single thread can have hundreds of in-flight queries:

```
Thread 1: → send query 1 → send query 2 → send query 3 → ...
           → receive result 1 → receive result 2 → ...
```

The same thread handles many requests concurrently, limited by CPU rather than blocking I/O.

### Language-Specific Async Patterns

The right async approach varies by language and framework:

| Language | Async Approach |
|----------|---------------|
| Python | `asyncio` + async driver, or `execute_concurrent_with_args` |
| Java | `executeAsync()` + CompletableFuture |
| Go | Goroutines (inherently async) |
| Node.js | Native async/await (event loop handles concurrency) |

---

## Examples

### Python — blocking (anti-pattern)
```python
# ANTI-PATTERN: blocks the thread for each query
def get_user_and_orders(user_id):
    user = session.execute(get_user_stmt, [user_id]).one()       # blocks
    orders = session.execute(get_orders_stmt, [user_id]).all()   # blocks
    return user, orders
```

### Python — async with asyncio
```python
from cassandra.cluster import Cluster
from cassandra.io.asyncioreactor import AsyncioConnection

cluster = Cluster(connection_class=AsyncioConnection)
session = cluster.connect()

async def get_user_and_orders(user_id):
    # Fire both queries concurrently — don't wait for one before starting the other
    user_future = session.execute_async(get_user_stmt, [user_id])
    orders_future = session.execute_async(get_orders_stmt, [user_id])

    user = (await user_future).one()
    orders = (await orders_future).all()
    return user, orders
```

### Java — blocking (anti-pattern)
```java
// ANTI-PATTERN: blocks the thread
public UserProfile getProfile(UUID userId) {
    Row user = session.execute(getUser.bind(userId)).one();         // blocks
    List<Row> orders = session.execute(getOrders.bind(userId)).all(); // blocks
    return buildProfile(user, orders);
}
```

### Java — async with CompletableFuture
```java
public CompletableFuture<UserProfile> getProfile(UUID userId) {
    CompletableFuture<AsyncResultSet> userFuture =
        session.executeAsync(getUser.bind(userId)).toCompletableFuture();

    CompletableFuture<AsyncResultSet> ordersFuture =
        session.executeAsync(getOrders.bind(userId)).toCompletableFuture();

    // Both queries in flight simultaneously
    return CompletableFuture.allOf(userFuture, ordersFuture)
        .thenApply(v -> buildProfile(userFuture.join().one(), ordersFuture.join().all()));
}
```

### Go — naturally async with goroutines
```go
// Go's concurrency model is inherently non-blocking
func getProfile(ctx context.Context, session *gocql.Session, userID gocql.UUID) (*UserProfile, error) {
    var user User
    var orders []Order
    var wg sync.WaitGroup
    var userErr, ordersErr error

    wg.Add(2)
    go func() {
        defer wg.Done()
        userErr = session.Query("SELECT * FROM users WHERE user_id = ?", userID).
            WithContext(ctx).Scan(&user.ID, &user.Name, &user.Email)
    }()
    go func() {
        defer wg.Done()
        // fetch orders...
    }()
    wg.Wait()

    if userErr != nil { return nil, userErr }
    if ordersErr != nil { return nil, ordersErr }
    return buildProfile(user, orders), nil
}
```

---

## Pulse Check

> A Java REST endpoint fetches a user's profile and their last 5 orders, then combines them into a response. Currently it calls `session.execute()` twice, sequentially.
>
> **What's wrong and how do you fix it?**

*(Expected answer: Two sequential blocking calls means the second query doesn't start until the first completes — total latency is query1 + query2 latency. Since the two queries are independent (orders don't depend on user data), they should run concurrently. Fix: use `session.executeAsync()` for both, combine with `CompletableFuture.allOf()`, and await both results together. Total latency becomes max(query1, query2) instead of query1 + query2.)*

---

## See Also

**In this session:**
- [In-Memory Joins on Large Datasets](./09-in-memory-joins.md)
- [Excessive Async Operations](./11-excessive-async.md)

**Reference:**
- [Drivers](../../general/drivers.md)
- [Prepared Statements](../../general/prepared-statements.md)
- [Thread Pools](../../general/thread-pools.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
