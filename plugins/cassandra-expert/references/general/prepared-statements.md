# Prepared Statements

Always use prepared statements for queries executed more than once. They are critical for performance (parsed once, reused), efficiency (less CPU on the cluster), and security (prevents CQL injection).

## Driver Behavior

| Language/Driver | Auto-Prepare? | Notes |
|----------------|---------------|-------|
| **Go (gocql)** | Yes | Automatically prepares queries on first execution |
| **Java** | No | Must explicitly call `session.prepare()` |
| **Python** | No | Must explicitly call `session.prepare()` |
| **Node.js** | No | Must explicitly prepare statements |
| **C#** | No | Must explicitly call `Prepare()` |

## Usage Examples

```python
# Python - WRONG (not prepared, parsed every time)
for user_id in user_ids:
    session.execute(f"SELECT * FROM users WHERE user_id = {user_id}")

# Python - CORRECT (prepared once, executed many times)
prepared = session.prepare("SELECT * FROM users WHERE user_id = ?")
for user_id in user_ids:
    session.execute(prepared, [user_id])
```

```java
// Java - WRONG (not prepared)
for (UUID userId : userIds) {
    session.execute("SELECT * FROM users WHERE user_id = " + userId);
}

// Java - CORRECT (prepared statement)
PreparedStatement prepared = session.prepare(
    "SELECT * FROM users WHERE user_id = ?"
);
for (UUID userId : userIds) {
    session.execute(prepared.bind(userId));
}
```

```go
// Go - Automatically prepared on first execution
for _, userId := range userIds {
    session.Query("SELECT * FROM users WHERE user_id = ?", userId).Exec()
}
```

## Best Practices

- Prepare statements at application startup for common queries
- Cache prepared statements and reuse them — never prepare inside a loop
- Use `?` placeholders, never string concatenation
- Only prepare queries that will be executed multiple times

## Server-Side Cache Configuration

```yaml
# cassandra.yaml

# Cassandra 5.0+ (requires unit suffix)
prepared_statements_cache_size: auto   # default — recommended

# Cassandra 4.0–4.1 (no unit suffix)
prepared_statements_cache_size_mb: auto
```

**Auto-sizing formula:** `max(heap / 256, 10MiB)`

| Heap | Auto cache size |
|------|----------------|
| 8GB | 32MB |
| 16GB | 64MB |
| 32GB | 128MB |
| 64GB | 256MB |

Start with `auto`. Only override after monitoring shows legitimate cache pressure.

## Metrics

```bash
# Via virtual table (4.1+)
SELECT prepared_statements_count, prepared_statements_evicted,
       prepared_statements_ratio, regular_statements_executed
FROM system_views.cql_metrics;

# Via JMX (all versions)
nodetool sjk mxdump -q "org.apache.cassandra.metrics:type=CQL,name=Prepared*"
```

| Metric | Healthy | Action needed |
|--------|---------|--------------|
| `PreparedStatementsCount` | Well below cache limit | > 50MB — investigate application |
| `PreparedStatementsEvicted` | Zero or low | > 5% eviction rate — investigate |
| `PreparedStatementsRatio` | > 0.8 | < 0.5 — application not using prepared statements |

## Warning: PreparedStatementsCount > 50MB

This almost always indicates an application problem — **do not increase the cache size** to compensate.

**Root causes:**
1. **String concatenation** — each unique query string is a separate cache entry, creating unlimited entries
2. **Preparing inside a loop** — `session.prepare()` called on every execution instead of once at startup
3. **Too many tables** — data model generating excessive unique query patterns

**Fix the application code first**, then monitor the count drop naturally.

## Eviction Rate

```
eviction_rate = PreparedStatementsEvicted / PreparedStatementsExecuted
```

- **< 1%** — healthy
- **1–5%** — monitor
- **> 5%** — investigate anti-patterns; if none found, increase cache size

## See Also

- `drivers.md` — driver links and auto-prepare behavior
