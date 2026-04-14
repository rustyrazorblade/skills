# Topic: Table Pattern — Time Series

## Objective
Design time-series tables that are efficient for high-volume append-only writes, support time-range reads, and stay bounded in partition size through bucketing.

## Why This Matters
Time series is one of Cassandra's strongest use cases — high write throughput, sequential disk access, simple append-only mutations. But it's also one of the easiest to get wrong. The natural first design (partition by entity, cluster by time) creates unbounded partitions that grow until they cause production incidents. Bucketing is the critical technique that makes time series work at scale.

---

## Concept

Time-series data shares three characteristics:
1. **Append-only**: records are written once, never updated
2. **Time-ordered**: reads want rows in time order
3. **High cardinality**: many entities (devices, users, events) each generating a stream

The natural fit for Cassandra:
- Partition key = entity identifier
- Clustering column = timestamp (usually DESC for "newest first")

The problem: an entity's partition grows forever. A sensor writing once per second accumulates 86,400 rows/day. After a year, one partition has 31M rows and is likely hundreds of megabytes or more.

### The Fix: Time Bucketing

Add a **time bucket** to the partition key. Instead of one partition per entity, you get one partition per entity per time period (day, hour, month — whatever keeps partitions under ~10MB).

```sql
-- BAD: one partition per sensor, grows forever
PRIMARY KEY (sensor_id, recorded_at)

-- GOOD: one partition per sensor per day, bounded
PRIMARY KEY ((sensor_id, bucket_day), recorded_at)
```

The trade-off: reads that span bucket boundaries require multiple queries (one per bucket). This is expected and manageable — calculate the list of buckets client-side.

### Choosing Bucket Size

| Write rate | Bytes per row | Max rows/bucket | Bucket size |
|------------|--------------|-----------------|-------------|
| 1/sec | 100 bytes | 86,400 | 1 day (~8.6MB) |
| 10/sec | 100 bytes | 8,640 | 1 hour (~8.6MB) |
| 100/sec | 500 bytes | 1,000 | 5 seconds (~500KB) |

Target: keep partitions under 10MB — that's the sweet spot. For partitions that are rarely read from, up to 100MB is acceptable. Calculate: `(rows/sec) × (bytes/row) × (seconds/bucket)`.

### TTL for Automatic Expiration

Time-series tables should almost always use TTL (covered in the TTL topic) to expire old data automatically. Combine bucketing with a table-level `default_time_to_live` so every row is written with an expiration, and old bucket partitions drop off naturally.

One caveat specific to time series: if you retain data for a short window (days or weeks), consider **lowering `gc_grace_seconds`** to reduce how long expired-row tombstones linger — but only if your repair cadence supports it. See the Table Options topic. (Repair isn't covered in detail in this training yet — see [Repair](../../general/repair.md) for the full reference.)

### Table-per-Bucket as a TTL Alternative

A more flexible approach is to use **monthly (or weekly) tables** and `DROP TABLE` when the data is no longer needed:

```sql
-- One table per month
CREATE TABLE sensor_readings_2025_01 ( ... );
CREATE TABLE sensor_readings_2025_02 ( ... );

-- When January data is expired, just drop it
DROP TABLE sensor_readings_2025_01;
```

This is especially useful when you need to **archive or offload data** to another system (cold storage, data warehouse) before deleting it — you can be certain the data has been moved before the table is dropped. With TTL, data disappears automatically whether or not you've had a chance to archive it.

---

## Examples

### Basic time series with day bucketing
```sql
CREATE TABLE sensor_readings (
    sensor_id uuid,
    bucket_day date,       -- 'YYYY-MM-DD' — one partition per sensor per day
    recorded_at timestamp,
    temperature double,
    humidity double,
    PRIMARY KEY ((sensor_id, bucket_day), recorded_at)
) WITH CLUSTERING ORDER BY (recorded_at DESC)
  AND default_time_to_live = 7776000;  -- 90 days

-- Write a reading
INSERT INTO sensor_readings (sensor_id, bucket_day, recorded_at, temperature, humidity)
VALUES (?, toDate(now()), toTimestamp(now()), ?, ?);

-- Read last hour of readings for a sensor
SELECT recorded_at, temperature, humidity
FROM sensor_readings
WHERE sensor_id = ?
  AND bucket_day = toDate(now())
  AND recorded_at > toTimestamp(now()) - 3600s
LIMIT 1000;
```

### Application-level bucket calculation (Python)
```python
from datetime import date, timedelta

write_reading = session.prepare("""
    INSERT INTO sensor_readings (sensor_id, bucket_day, recorded_at, temperature, humidity)
    VALUES (?, ?, ?, ?, ?)
    USING TTL 7776000
""")

read_range = session.prepare("""
    SELECT recorded_at, temperature, humidity
    FROM sensor_readings
    WHERE sensor_id = ?
      AND bucket_day = ?
      AND recorded_at >= ?
      AND recorded_at <= ?
    ORDER BY recorded_at ASC
""")

def get_readings_for_range(sensor_id, start_dt, end_dt):
    """Queries across day buckets transparently."""
    results = []
    current = start_dt.date()
    end_date = end_dt.date()

    while current <= end_date:
        rows = session.execute(read_range, [sensor_id, current, start_dt, end_dt])
        results.extend(rows)
        current += timedelta(days=1)

    return results
```

### Application-level bucket calculation (Java)
```java
PreparedStatement writeReading = session.prepare(
    "INSERT INTO sensor_readings (sensor_id, bucket_day, recorded_at, temperature, humidity) " +
    "VALUES (?, ?, ?, ?, ?) USING TTL 7776000"
);

PreparedStatement readRange = session.prepare(
    "SELECT recorded_at, temperature, humidity FROM sensor_readings " +
    "WHERE sensor_id = ? AND bucket_day = ? AND recorded_at >= ? AND recorded_at <= ?"
);

public List<Row> getReadings(UUID sensorId, Instant start, Instant end) {
    List<Row> results = new ArrayList<>();
    LocalDate current = start.atZone(ZoneOffset.UTC).toLocalDate();
    LocalDate endDate = end.atZone(ZoneOffset.UTC).toLocalDate();

    while (!current.isAfter(endDate)) {
        results.addAll(
            session.execute(readRange.bind(sensorId, current, start, end)).all()
        );
        current = current.plusDays(1);
    }
    return results;
}
```

### Application-level bucket calculation (Go)
```go
// gocql automatically prepares queries on first execution
func getReadings(session *gocql.Session, sensorID gocql.UUID, start, end time.Time) ([]Reading, error) {
    var results []Reading
    current := start.Truncate(24 * time.Hour)

    for !current.After(end) {
        iter := session.Query(
            `SELECT recorded_at, temperature, humidity FROM sensor_readings
             WHERE sensor_id = ? AND bucket_day = ? AND recorded_at >= ? AND recorded_at <= ?`,
            sensorID, current, start, end,
        ).Iter()

        var r Reading
        for iter.Scan(&r.RecordedAt, &r.Temperature, &r.Humidity) {
            results = append(results, r)
        }
        if err := iter.Close(); err != nil {
            return nil, err
        }
        current = current.Add(24 * time.Hour)
    }
    return results, nil
}
```

---

## Pulse Check

> You're building an IoT platform. Each device sends 1 event per second. Each event is ~200 bytes. You want to keep 30 days of history.
>
> **Without bucketing, how large would one device's partition grow over 30 days? What bucket size would you choose to stay under 10MB per partition?**

*(Expected answer: Without bucketing: 1 event/sec × 200 bytes × 86,400 sec/day × 30 days = ~518MB — too large. With daily buckets: 1 event/sec × 200 bytes × 86,400 sec/day = ~17MB per partition. That's within the acceptable range (sweet spot is under 10MB, up to 100MB is fine for infrequently read data). Daily buckets are a reasonable choice here given the known, constant write rate.)*

---

## See Also

**In this session:**
- [TTL (Time-To-Live)](./14-ttl.md)
- [Pattern: Ordered Map](./18-pattern-ordered-map.md)
- [Compaction Overview](./13-compaction-overview.md)

**Reference:**
- [Time Series Data Modeling](../../general/time-series.md)
- [Large Partitions](../../general/large-partitions.md)
- [Compaction](../../general/compaction.md)
- [Streaming](../../general/streaming.md)
