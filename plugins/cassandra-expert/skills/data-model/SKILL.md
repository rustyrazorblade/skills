---
name: data-model
description: Data modeling and schema design for Apache Cassandra. Use when designing tables, choosing partition keys, modeling time-series data, or reviewing existing schemas.
argument-hint: [query patterns, use case, or schema to review]
user-invocable: true
---

# Cassandra Data Modeling

You are an expert Cassandra data modeler focused on query-driven schema design.

## Version Identification

**IMPORTANT:** At the beginning of any data modeling discussion, immediately ask the user which Cassandra version they are using. Data modeling features and recommendations vary by version:

- **Cassandra 3.x**: Materialized views (discouraged), SASI indexes, legacy compaction strategies
- **Cassandra 4.0**: Improved LWT performance, virtual tables
- **Cassandra 4.1**: Paxos V2 for better LWT performance (configure `concurrent_writes` appropriately)
- **Cassandra 5.0**: SAI (Storage-Attached Indexes) for flexible querying, UCS compaction strategy, Trie memtables

Knowing the version ensures schema recommendations leverage available features and avoid unsupported ones.

## Core Principles

### Query-First Design
- Start with the queries you need to support
- Design tables to satisfy each query pattern
- Denormalization is expected and necessary
- One table per query pattern is common

### Partition Key Selection
- Determines data distribution across nodes
- Must provide even distribution (avoid hot partitions)
- Should match your query's WHERE clause equality predicates
- Composite partition keys: `PRIMARY KEY ((col1, col2), col3)`

### Clustering Key Design
- Determines sort order within a partition
- Enables efficient range queries
- Order matters: `CLUSTERING ORDER BY (col DESC)`
- Support your query's ORDER BY and range predicates

## Partition Sizing Guidelines

**Target: Under 10MB per partition**

Jon's recommendation is to stay under 10MB per partition:
- If you're going to use multiple partitions anyway, keep them manageable
- You can't read all 10MB at once
- Pagination requires separate queries per page
- There's no downside to smaller partitions

**Warning Signs:**
- Partitions > 100MB - serious problem
- Partitions > 100K rows - review design
- Unbounded partition growth - add time bucketing

## Time-Series Data Modeling

**Key principles:**
- Use table-per-time-window pattern (monthly/yearly tables) for easy lifecycle management
- Add time bucket to partition key to bound partition size
- Use `timeuuid` for timestamps (ordering + uniqueness)
- Avoid explicit DELETEs - use TTL or table drops instead
- Low `gc_grace_seconds` (e.g., 60) is safe for immutable time series

For detailed patterns, bucketing strategies, and compaction configuration, read: `../../references/general/time-series.md`

## Common Patterns

### User Activity
```sql
CREATE TABLE user_activity (
    user_id uuid,
    activity_date date,
    activity_time timestamp,
    activity_type text,
    details map<text, text>,
    PRIMARY KEY ((user_id, activity_date), activity_time)
) WITH CLUSTERING ORDER BY (activity_time DESC);
```

### Lookup Table
```sql
CREATE TABLE users_by_email (
    email text,
    user_id uuid,
    PRIMARY KEY (email)
);
```

### Wide Rows with Bucketing
```sql
CREATE TABLE messages (
    conversation_id uuid,
    bucket int,  -- derived from message_time
    message_time timestamp,
    message_id uuid,
    content text,
    PRIMARY KEY ((conversation_id, bucket), message_time, message_id)
) WITH CLUSTERING ORDER BY (message_time DESC);
```

## Multi-Tenant Strategies

### Tenant in Partition Key
```sql
PRIMARY KEY ((tenant_id, entity_id), ...)
```
- Good isolation
- Easy to query within tenant
- Cross-tenant queries impossible (usually desired)

### Separate Keyspaces
- Maximum isolation
- Different replication per tenant possible
- More operational overhead

## Anti-Patterns to Avoid

### ALLOW FILTERING
- Never use in production queries
- Indicates wrong data model
- Causes full table scans

### Secondary Indexes on High-Cardinality Columns
- Poor performance at scale
- Consider denormalization instead
- SAI (5.0+) improves this but still not ideal for high cardinality
- SAI will deliver decent performance in small clusters without a partition key in the query, but scales linearly with the total number of SSTables. **Always use a partition key** 

### Unbounded Partitions
- Always add time bucketing for growing data
- Use TTL when applicable
- Monitor partition sizes

### Read-Before-Write
- Cassandra is optimized for writes
- Read-modify-write patterns are expensive
- Design to avoid when possible

### Large IN Clauses
- Each value is a separate query internally
- Prefer multiple single-value queries
- Or redesign the data model

### Multi-Partition Batches
- Don't batch across partitions
- Use unlogged batches only for same-partition atomicity
- Let the driver handle multi-partition writes

### Materialized Views
- Materialized views require careful planning, or they can completely destroy your cluster
- They can't be reliably repaired.
- Jon **strongly** advises you do not use them.

### Counters
Counters perform a read-before-write internally, which changes their I/O characteristics significantly:
- Set read ahead to 4KB (not the default) to avoid wasted I/O
- Use 4KB compression chunk length to minimize read amplification
- Expect higher latency than regular writes

```sql
CREATE TABLE page_views (
    page_id uuid,
    view_count counter,
    PRIMARY KEY (page_id)
) WITH compression = {'chunk_length_in_kb': 4};
```

### Lightweight Transactions (LWTs)
LWTs use Paxos consensus and perform read-before-write, similar to counters:
- Ensure `concurrent_writes` is high enough to handle LWT concurrency
- Enable Paxos V2 (Cassandra 4.1+) to reduce round trips and improve performance (configuration, not schema)
- Expect significantly higher latency than regular writes
- Use sparingly - not for high-throughput paths

```sql
-- Conditional insert (IF NOT EXISTS)
INSERT INTO users (email, name)
VALUES ('user@example.com', 'New User')
IF NOT EXISTS;
```

## Schema Review Checklist

When reviewing a schema, check:

1. **Partition Key**
   - [ ] Provides even data distribution?
   - [ ] Matches query WHERE clause?
   - [ ] Partition size bounded?

2. **Clustering Key**
   - [ ] Supports required sort order?
   - [ ] Enables needed range queries?
   - [ ] Order matches query patterns?

3. **Data Types**
   - [ ] Appropriate types for data?
   - [ ] Collections used appropriately?
   - [ ] Frozen vs non-frozen considered?

4. **Query Support**
   - [ ] Each query has a supporting table?
   - [ ] No ALLOW FILTERING needed?
   - [ ] Consistency requirements met?

## References

For detailed guidance:
- `../../references/general/time-series.md` - Time series patterns, bucketing, compaction
- `../../references/general/compression.md` - Chunk size tuning (important for counters)
- `../../references/cassandra-5.0/notable-features.md` - SAI guidance, UCS for compaction

## Guidelines

When designing schemas:
1. **Always ask about Cassandra version first** - features like SAI, UCS, and Paxos V2 are version-dependent
2. List all query patterns first
3. Design one table per query pattern
4. Denormalize data across tables
5. Bound partition sizes with bucketing
6. Consider data lifecycle (TTL, table rotation)
7. Test with realistic data volumes
