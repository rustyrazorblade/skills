# journal.md — Lab Journal

`journal.md` lives at `docs/journal.md` inside the lab workspace directory. It is a human-readable record of everything done to the environment, written for the operator and for anyone reviewing the work later.

## Create It Immediately

The very first thing you do in any skill is create `docs/journal.md` if it does not exist (creating `docs/` if needed), then open a new session entry:

```markdown
# Lab Journal

## 2026-05-23 — <brief description of what this session is doing>
```

Do not wait. Create it before running any commands.

## Update It Continuously

After every command or observation, append an entry. Do not batch updates — write each one as it happens so the record is accurate even if the session is interrupted.

```markdown
### 10:34 Checked cluster status
Both DCs up. dc1: 3 nodes, dc2: 3 nodes. All UN.

### 10:36 Selected Cassandra 5.0 on dc1
`easy-db-lab cassandra use 5.0` — completed successfully.

### 10:41 Updated cassandra.patch.yaml on dc1
Set num_tokens: 4, enabled trie memtables. Pushed and restarted.

### 10:55 Started KeyValue stress test
`cassandra stress start --name baseline -- KeyValue -d 30m --threads 100`
op/s: 24,500 — p99 read: 3.2ms, p99 write: 1.8ms
```

## What to Record

- Every command run and whether it succeeded or failed
- Key output: node counts, versions, IPs, op/s, latency percentiles, error messages
- Configuration changes and what was changed
- Decisions made and why
- Anything unexpected or worth investigating
- Results from stress tests and benchmarks

## What to Skip

- Routine status polls with no new information
- Repeated identical commands with identical output

## Format

```markdown
# Lab Journal

## <YYYY-MM-DD> — <session goal>

### <HH:MM> <action or observation>
<what was done or found — one or two sentences>
<key output or metrics if relevant>
```

If `docs/journal.md` already exists, read it first to understand the full context of what has been done to this environment before taking any action.

## Grafana Screenshots

When observing performance results — stress test throughput, latency, compaction, anything you'd want to reference later — download a screenshot from Grafana and embed it in the journal entry.

Save screenshots to `docs/images/` and reference them inline:

```markdown
### 11:22 KeyValue baseline — 30m run complete
op/s: 24,500 — p99 read: 3.2ms, p99 write: 1.8ms

![KeyValue baseline throughput](images/baseline-throughput.png)
![KeyValue baseline latency](images/baseline-latency.png)
```

Name files descriptively — `<test-name>-<metric>.png` — so the images directory is navigable on its own.
