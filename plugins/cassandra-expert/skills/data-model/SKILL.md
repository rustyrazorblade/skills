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

## Denormalization Strategy

**Cassandra has no joins.** To support multiple query patterns, you must denormalize data across multiple tables. Understanding the trade-offs is critical for effective schema design.

### The Economic Trade-off

**Denormalization trades disk space for query performance:**

- **Disk space is cheap** - Storage costs are low and continue to decrease
- **CPU and memory are expensive** - Performing joins requires significant compute resources
- **Network I/O is expensive** - Fetching data from multiple tables adds latency

**The calculation:**
- Storing the same data in 3 different tables uses 3x disk space
- But eliminates the need for application-level joins (CPU + memory)
- Eliminates multiple round-trips to the database (network latency)
- Result: Better performance at lower operational cost

### When Denormalization Works Well

**Immutable or rarely-changing data:**
- User profiles that change infrequently
- Historical records (orders, transactions, logs)
- Reference data (product catalog, configuration)
- Time-series data (metrics, events, sensor readings)

**Why it works:** Write once, read many times. The cost of denormalization is paid once at write time.

### When Denormalization Is Challenging

**Highly mutable data:**
- Data that changes frequently across many denormalized tables
- Real-time inventory, live scores, rapidly updating counters
- Data requiring immediate consistency across all copies

**The challenge:** Every update must be written to multiple tables to maintain consistency. This creates:
- Higher write amplification (one logical update = N physical writes)
- Potential for inconsistency if writes fail partially
- More complex application logic to coordinate updates

**Evaluate the trade-off:**
- **Choose denormalization (disk)** when:
  - Data is immutable or changes infrequently
  - Read performance is critical
  - Eventual consistency is acceptable
  - Storage cost is less than compute cost

- **Consider alternatives (CPU)** when:
  - Data is highly mutable and updated frequently
  - Immediate consistency across all views is required
  - Write amplification would be excessive
  - Alternative: Accept slower queries by fetching related data separately

### Denormalization Patterns

**Pattern 1: Complete entity duplication**
```sql
-- User entity table
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email text,
    name text,
    created_at timestamp
);

-- Duplicate user data in posts table for efficient queries
CREATE TABLE posts_by_user (
    user_id uuid,
    post_time timestamp,
    post_id uuid,
    user_name text,        -- Denormalized from users
    user_email text,       -- Denormalized from users
    title text,
    content text,
    PRIMARY KEY (user_id, post_time, post_id)
);
```

**Pattern 2: Bi-directional mapping tables**
```sql
-- Query: "What movies has this user liked?"
CREATE TABLE movies_by_user (
    user_id uuid,
    movie_id uuid,
    liked_at timestamp,
    movie_title text,      -- Denormalized from movies
    PRIMARY KEY (user_id, movie_id)
);

-- Query: "Which users liked this movie?"
CREATE TABLE users_by_movie (
    movie_id uuid,
    user_id uuid,
    liked_at timestamp,
    user_name text,        -- Denormalized from users
    PRIMARY KEY (movie_id, user_id)
);
```

**Pattern 3: Aggregated/derived data**
```sql
-- Store pre-computed aggregates to avoid computation at read time
CREATE TABLE user_stats (
    user_id uuid PRIMARY KEY,
    total_posts int,
    total_likes int,
    last_post_at timestamp
);
```

### Managing Consistency Across Denormalized Tables

**Write to multiple tables in your application:**
```python
# When creating a post, write to multiple tables
def create_post(user_id, title, content):
    # Write to posts table
    session.execute(posts_insert, [user_id, timestamp, title, content])

    # Write to user timeline
    session.execute(timeline_insert, [user_id, timestamp, title])

    # Write to global feed
    session.execute(feed_insert, [timestamp, user_id, title])
```

**Handling partial failures:**
- Use LOGGED batches when writing denormalized data to multiple tables
  - Ensures all writes eventually succeed (Cassandra will replay if any part fails)
  - Does NOT provide atomicity or isolation - readers may see partial results
  - Has performance overhead - only use when you need the eventual guarantee
- Use UNLOGGED batches for same-partition writes when grouping for convenience
- Implement application-level retry logic for critical operations
- Accept eventual consistency - it's okay if tables are briefly out of sync
- Use idempotent writes where possible (same write can be repeated safely)

**Updating denormalized data:**
- If denormalized data changes (e.g., user changes their name), you must update all copies
- Evaluate: Is the update frequency worth the read performance gain?
- Consider: Can you live with stale data for some period?

### Denormalization Checklist

When designing denormalized tables, ask:

1. **Is the data immutable or rarely-changing?**
   - Yes → Denormalize freely
   - No → Evaluate write amplification cost

2. **How many tables will contain this data?**
   - 2-5 tables → Usually acceptable
   - 10+ tables → Consider if all copies are necessary

3. **What's the update frequency?**
   - Daily/weekly → Denormalization cost is low
   - Per second → Carefully evaluate disk vs CPU trade-off

4. **Can you tolerate eventual consistency?**
   - Yes → Denormalization is easier
   - No → Consider alternative approaches or LWTs

5. **Is read performance critical?**
   - Yes → Denormalization pays off
   - No → May not be worth the complexity

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

## Core Table Patterns

These three patterns cover 95% of all Cassandra use cases. Understanding which pattern fits your access requirements is the key to effective schema design.

### 1. Single Key Pattern (Entity Table)

**Use when:** You need simple key-value lookups with no ordering requirements.

**Characteristics:**
- Partition key only (no clustering columns, or clustering used only for uniqueness)
- One row per partition (or small, bounded number of rows)
- Fast point lookups by key
- No range queries needed

**Examples:**
```sql
-- User profile lookup by ID
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email text,
    name text,
    created_at timestamp
);

-- Configuration settings
CREATE TABLE app_config (
    config_key text PRIMARY KEY,
    config_value text,
    updated_at timestamp
);
```

**When to use:** User profiles, configuration lookups, any entity retrieval by unique identifier.

### 2. Ordered Map Pattern

**Use when:** You need to store multiple related items and retrieve them in sorted order.

**Characteristics:**
- Partition key + clustering columns
- Multiple rows per partition, sorted by clustering key
- Supports range queries and ordering within partition
- Bounded partition size (use bucketing if needed)

**Examples:**
```sql
-- Mapping table: movies liked by user (one-to-many or many-to-many)
CREATE TABLE movies_by_user (
    user_id uuid,
    movie_id uuid,
    liked_at timestamp,
    rating int,
    PRIMARY KEY (user_id, movie_id)
);

-- Bi-directional mapping for many-to-many: users who liked a movie
CREATE TABLE users_by_movie (
    movie_id uuid,
    user_id uuid,
    liked_at timestamp,
    rating int,
    PRIMARY KEY (movie_id, user_id)
);

-- User's posts, ordered by creation time
CREATE TABLE posts_by_user (
    user_id uuid,
    post_time timestamp,
    post_id uuid,
    title text,
    content text,
    PRIMARY KEY (user_id, post_time, post_id)
) WITH CLUSTERING ORDER BY (post_time DESC);
```

**When to use:** Mapping tables (inverted indexes), comments, messages, activity feeds, audit logs - anywhere you need to relate entities or retrieve items in sorted order. For many-to-many relationships, create bi-directional mapping tables to support queries from both sides.

### 3. Time Series Pattern

**Use when:** You have time-stamped data with continuous writes and time-based queries.

**Characteristics:**
- Ordered map pattern with time-based clustering
- Partition key includes time bucket to bound partition size
- Immutable data (writes only, no updates)
- Often uses TTL for automatic expiration
- Query by time ranges within a partition

**Examples:**
```sql
-- Sensor readings with daily bucketing
CREATE TABLE sensor_data (
    sensor_id uuid,
    date date,           -- bucket to limit partition size
    reading_time timestamp,
    temperature decimal,
    humidity decimal,
    PRIMARY KEY ((sensor_id, date), reading_time)
) WITH CLUSTERING ORDER BY (reading_time DESC);

-- Application metrics with hourly bucketing
CREATE TABLE metrics (
    metric_name text,
    hour timestamp,      -- truncated to hour for bucketing
    metric_time timestamp,
    value double,
    tags map<text, text>,
    PRIMARY KEY ((metric_name, hour), metric_time)
) WITH CLUSTERING ORDER BY (metric_time DESC)
AND default_time_to_live = 604800;  -- 7 days
```

**When to use:** IoT sensor data, metrics, logs, event streams - any append-only time-stamped data.

**Critical for time series:**
- Always include time bucketing in partition key (daily, hourly, monthly)
- Use TTL instead of DELETE for expiration
- Consider table-per-time-window for easy lifecycle management
- Use TWCS compaction (pre-5.0) or UCS (5.0+)

For detailed time series guidance, read: `../../references/general/time-series.md`

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

## Compaction Strategy Selection

**Compaction strategy is a table-level setting that must be chosen at table creation time.** The strategy determines how SSTables are merged and has a significant impact on read performance, write amplification, and operational characteristics.

### Strategy Selection by Version

**Cassandra 5.0+:**

Use **UCS (Unified Compaction Strategy)** for all workloads:

```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email text,
    name text
) WITH compaction = {
    'class': 'UnifiedCompactionStrategy'
};
```

UCS is designed to handle all workload types efficiently. It replaces the need to choose between LCS, STCS, and TWCS.

**Pre-5.0 (Cassandra 3.x and 4.x):**

Choose based on your table pattern:

**For time-series tables with TTL:**
- Use **TWCS (Time Window Compaction Strategy)**
- Organizes data into time windows matching your TTL
- Enables efficient dropping of entire SSTables when data expires
- Avoids tombstone accumulation

```sql
CREATE TABLE sensor_data (
    sensor_id uuid,
    date date,
    reading_time timestamp,
    temperature decimal,
    PRIMARY KEY ((sensor_id, date), reading_time)
) WITH compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',
    'compaction_window_size': 1
}
AND default_time_to_live = 2592000;  -- 30 days
```

**For general workloads (entity tables, ordered maps):**
- Use **LCS (Leveled Compaction Strategy)** as the default
- Better read performance through size-tiered organization
- More predictable read latencies
- Higher write amplification than STCS but acceptable for most workloads

```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email text,
    name text
) WITH compaction = {
    'class': 'LeveledCompactionStrategy'
};
```

**STCS (Size-Tiered Compaction Strategy) - Limited use case:**
- ONLY use STCS in pre-5.0 when LCS cannot keep up with compaction
- Not appropriate for time-series workloads (use TWCS instead)
- Creates increasingly large SSTables over time
- Large SSTables slow down streaming operations (bootstrap, decommission, repair)
- If you find LCS falling behind, STCS may be necessary, but consider upgrading to 5.0+ for UCS

### Quick Reference

| Cassandra Version | Table Type | Strategy | Notes |
|------------------|------------|----------|-------|
| **5.0+** | All workloads | UCS | Recommended for all use cases |
| **Pre-5.0** | Time series with TTL | TWCS | Time window-based compaction |
| **Pre-5.0** | General workloads | LCS | Default for most tables |
| **Pre-5.0** | High write volume | STCS | Only when LCS can't keep up |

### Changing Compaction Strategy

**Warning:** Changing compaction strategy on existing tables requires a full recompaction and can be resource-intensive.

```sql
-- Change strategy (triggers background recompaction)
ALTER TABLE users WITH compaction = {
    'class': 'UnifiedCompactionStrategy'
};
```

For detailed compaction tuning, migration guidance, and troubleshooting, read: `../../references/general/compaction.md`

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
- Don't batch across partitions for "performance"
- Batches are not a performance optimization
- Use LOGGED batches only when you need eventual guarantee across multiple tables
- Use UNLOGGED batches for same-partition writes when grouping for convenience
- Let the driver handle multi-partition writes efficiently

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
