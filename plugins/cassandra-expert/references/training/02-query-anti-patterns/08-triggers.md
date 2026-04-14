# Topic: Triggers

## Objective
Understand why Cassandra triggers are a legacy hack that expose internal APIs in the write path, and what to use instead when you need to react to mutations.

## Why This Matters
Triggers look like a convenient way to hook custom logic into writes — "when a row is inserted, also do X." In practice they are one of the most dangerous features in Cassandra. They run arbitrary Java inside the coordinator's write path, expose unstable internal APIs (`Mutation`, `Partition`, `PartitionUpdate`), fire on only one node rather than all replicas, and have no retry or consistency guarantees. A trigger that looks fine in staging can corrupt data or crash coordinators in production, and upgrades routinely break trigger code because the internals they depend on are not a stable surface.

---

## Concept

### What Triggers Are

Cassandra supports user-installed triggers via `CREATE TRIGGER`, backed by a Java class implementing `org.apache.cassandra.triggers.ITrigger`. The trigger's `augment()` method is called on the coordinator when a mutation arrives, and can return additional mutations to be applied alongside the original write.

```sql
CREATE TRIGGER audit_trigger ON my_keyspace.users
USING 'com.example.AuditTrigger';
```

The trigger JAR must be placed in `conf/triggers/` on every node. The `ITrigger` interface hands your code the raw `Partition` object — an internal Cassandra type — and expects you to return raw `Mutation` objects.

### Why Triggers Are an Anti-Pattern

**1. They expose internal, unstable APIs.**
`Mutation`, `Partition`, `PartitionUpdate`, and friends are implementation details of the storage engine. They change between releases — sometimes between minor releases. Trigger code that works on 4.0 may not compile on 4.1, and may compile but silently misbehave on 5.0. There is no stable contract, no deprecation policy, and no migration guide when internals shift.

**2. They run in the write path, on the coordinator only.**
The trigger fires on the **coordinator** that received the write — not on each replica. That has two consequences:

- **Extra mutations are only generated once**, on the coordinator, and then replicated like any other write. If the coordinator crashes mid-trigger, you get a partial result: the original mutation may or may not have been sent to replicas, the trigger's extra mutations may or may not have been generated, and there is no rollback.
- **Trigger latency is write latency.** Whatever your trigger does — logging, producing a message, writing to another table — happens synchronously inside the write path. Slow trigger code directly increases client write latency and ties up coordinator threads.

**3. There are no atomicity or retry guarantees.**
The original write and the trigger's extra mutations are not applied atomically. The write can succeed and the trigger's mutations can fail (or vice versa). There is no automatic retry and no mechanism to detect the mismatch after the fact. You end up with silent data inconsistency that you only discover when something else breaks.

**4. They run arbitrary code inside the database JVM.**
A bug in a trigger — an infinite loop, an OOM, an unhandled exception — directly impacts the Cassandra node. There is no sandbox. A single bad deploy of a trigger JAR can take down a cluster.

**5. They don't fire on all the paths you expect.**
Triggers fire on regular writes, but **not** on hints being replayed, **not** on repair streaming, and **not** on bulk loads via `sstableloader`. If you're using a trigger to maintain a derived view or audit log, any data that arrives via these paths is invisible to your trigger. Your "audit log" has holes in it.

**6. They are effectively deprecated in practice.**
Nobody ships new features for triggers. The community consensus — including guidance from the Cassandra PMC — is that triggers were an early experiment that should not be used, and that CDC is the supported replacement for mutation-observation use cases.

### What To Use Instead

**For "react to writes" use cases: CDC (Change Data Capture).**

CDC writes a log of mutations to a dedicated directory as they happen, and an external process consumes that log. This gives you:

- A stable, documented format (the CDC log is an append-only stream of `Mutation` records with a documented reader API)
- Decoupling from the write path — your consumer runs out-of-process, so it cannot take down a node
- Retry and replay — the log is persistent; you can reprocess it
- Coverage of all replicas — CDC is enabled per-table and every replica writes its own CDC log, so you don't lose data from hints, repair, or coordinator failures

```sql
-- Enable CDC on a table
ALTER TABLE my_keyspace.users WITH cdc = true;
```

An external consumer (often a Kafka Connect worker, a custom Java app using the CDC reader, or a tool like Debezium) tails the CDC directory and publishes mutations downstream.

**For "maintain a derived table" use cases: do it in the application.**

If you want every write to `users` to also update `users_by_email`, do both writes from your application using a `BATCH` (logged batch for multi-partition atomicity, or unlogged if you accept best-effort). This is explicit, debuggable, and doesn't depend on database internals.

```sql
BEGIN BATCH
  INSERT INTO users (user_id, email, name) VALUES (?, ?, ?);
  INSERT INTO users_by_email (email, user_id, name) VALUES (?, ?, ?);
APPLY BATCH;
```

**For "audit log" use cases: write the audit row from the application.**

Same pattern — two writes from the app, either in a batch or fire-and-forget. You control the format, you control the retries, and you don't couple your audit trail to Cassandra internals.

---

## Examples

### Anti-pattern: audit trigger
```sql
-- Install a Java class that hooks every write and produces a Kafka message
CREATE TRIGGER audit_trigger ON my_keyspace.orders
USING 'com.example.AuditKafkaTrigger';
```

Problems with this setup:
- If the Kafka producer is slow, write latency on `orders` spikes
- If the Kafka producer throws, the write may fail — or worse, succeed without the audit message
- Orders arriving via `sstableloader` or repair streaming will never appear in the audit log
- Upgrading Cassandra may silently break the trigger because `PartitionUpdate` changed shape

### Correct: CDC + external consumer
```sql
ALTER TABLE my_keyspace.orders WITH cdc = true;
```

```yaml
# cassandra.yaml
cdc_enabled: true
cdc_raw_directory: /var/lib/cassandra/cdc_raw
cdc_total_space_in_mb: 4096
```

An external process (Debezium, a custom consumer, etc.) reads the CDC log and publishes to Kafka. Cassandra write latency is unaffected; the consumer can crash and restart without losing data.

### Correct: application-level derived table
```python
# Application code — explicit, debuggable, no internals exposed
batch = BatchStatement(batch_type=BatchType.LOGGED)
batch.add(insert_user, (user_id, email, name))
batch.add(insert_user_by_email, (email, user_id, name))
session.execute(batch)
```

### Checking for triggers in an existing cluster
```sql
-- List all triggers currently installed
SELECT keyspace_name, table_name, trigger_name, options
FROM system_schema.triggers;
```

If this query returns rows in a production cluster, investigate — each one is a liability.

---

## Pulse Check

> An engineer on your team proposes installing a trigger on the `payments` table so that every successful payment automatically writes a row to `payment_audit` and publishes a message to Kafka. "It keeps the audit logic in one place and the application doesn't have to worry about it."
>
> **Why is this a bad idea, and what should they do instead?**

*(Expected answer: Triggers run on the coordinator only, in the write path, against unstable internal APIs. The Kafka publish will directly add latency to every payment write; a slow broker becomes a slow database. There are no atomicity guarantees between the original payment write, the audit row, and the Kafka message — any subset of them can succeed while the others fail, silently. Triggers also don't fire on hints, repair, or bulk loads, so the audit log will have gaps. The right approach is either (a) do the `payments` + `payment_audit` writes from the application in a logged batch, and publish to Kafka from the application after the write succeeds, or (b) enable CDC on `payments` and run an external consumer that reads the CDC log and writes to both the audit table and Kafka. CDC decouples the consumer from the write path and is the supported replacement for trigger-style use cases.)*

---

## See Also

**In this session:**
- [BATCH Misuse](./05-batch-misuse.md)
- [Lightweight Transactions (LWT)](./06-lightweight-transactions.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
