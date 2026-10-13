# journal.md — Lab Journal

The journal is the file with the role `<journal>`: `docs/4-journal.md` in a single or multi-DC workspace, and `docs/4-journal-<arm>.md` for an arm agent.  `report.md` defines the roles.  The journal is a human-readable record of everything done to the environment, written for the operator and for anyone reviewing the work later.  It is in the appendix of the lab report.

## Create It Immediately

`setup-cluster.sh` creates `<journal>` from the scaffold.  If `docs/SUMMARY.md` does not exist yet, the skill runs `setup-cluster.sh` first, as its own instructions say.  Then, before any other command, open a new session entry in `<journal>`:

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

If `<journal>` already holds entries, read it first to understand the full context of what has been done to this environment before taking any action.

## Measurements Go to the Evidence Tier

A measurement that the report states goes to the evidence tier, not to the journal.  After a measuring step, run `report-graph.py fetch` and `plot`, and append the evidence block to `2-evidence.md`, per the Graphs section of `report.md`.  In the journal, record the commands and the key numbers as they happen.

A Grafana render image is optional.  If you keep one, it goes in the journal only, in the appendix.  Download it to `docs/images/` and embed it from there; never link to Grafana:

```markdown
### 11:22 KeyValue baseline: 30m run complete
op/s: 24,500; p99 read: 3.2ms, p99 write: 1.8ms

![KeyValue baseline dashboard](images/baseline-dashboard.png)
```

Name files descriptively, `<test-name>-<metric>.png`, so the images directory is navigable on its own.
