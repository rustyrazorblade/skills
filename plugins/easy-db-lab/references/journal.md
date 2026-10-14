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

After every command or observation, append an entry. Do not batch updates — write each one as it happens so the record is accurate even if the session is interrupted.  Use the entry format in "Format" below.

````markdown
### 10:34 Checked cluster status

Both DCs are up.

- **dc1:** 3 nodes, all UN.
- **dc2:** 3 nodes, all UN.

### 10:36 Selected Cassandra 5.0 on dc1

- **Result:** exit 0.

```bash
$EDB cassandra use 5.0
```

### 10:41 Updated cassandra.patch.yaml on dc1

- **Config:** `num_tokens: 4`, trie memtables on.
- **Result:** pushed and restarted; all nodes UN.

### 10:55 Started KeyValue stress test

- **Result:** running, 30 minutes.

```bash
$EDB cassandra stress start --name baseline -- KeyValue -d 30m --threads 100
```

### 11:26 KeyValue stress test: complete

- **Throughput:** 24,500 op/s.
- **Latency:** p99 read 3.2ms, p99 write 1.8ms.

**Next:** fetch and render the evidence for the baseline run.
````

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
- Each pass of a loop, such as the check passes or the retries of one command.  Write one bullet for the whole loop.

## Format

```markdown
# Lab Journal

## <YYYY-MM-DD> — <session goal>

### <HH:MM> <action or observation>

<one short summary sentence>

- **<label>:** <outcome first, then the detail>
- **<label>:** <one fact per bullet>

**Next:** <the next step, when it is not obvious>
```

Each entry follows these rules, so that it is easy to read in the book:

- Put a blank line after the heading and between every block.  Markdown joins lines with no blank line between them into one paragraph.
- Write one short summary sentence.  Omit it when the bullets say everything.
- Write one bullet per fact.  Put the outcome first, and the label in bold.
- Put each command in a fenced block after the bullets, never inline in a sentence.  Shorten long paths through variables, such as `$EDB`, `$DOCS`, and `$TEST_DIR`.
- Keep each line to 160 characters or fewer.  In a code block, wrap a long command with `\`.
- A failure gets a `**Result: failed**` bullet with the error.
- An entry that starts a long step gets its result in the same entry, or in a follow-up entry that names the step.
- A loop, such as the check passes or the retries of one command, gets one bullet.  For example: "**Check:** 5 passes; the final pass is clean.  Details are in `5-issues.md`."
- Paste raw tool output only in a fenced block.

A failure entry looks like this:

````markdown
### 10:58 Fetched the baseline throughput

The fetch through the SOCKS proxy failed.

- **Result: failed** with `cannot reach Mimir: ConnectTimeout`.
- **Tunnel:** dead; `status` restarted it on a new port.

**Next:** fetch again through the new port.

```bash
report-graph.py fetch --mimir-url "$MIMIR_URL" --tenant "$TENANT" --query "$QUERY" \
  --start "$START" --end "$END" --step 30s --name throughput --docs "$DOCS" --proxy "$PROXY"
```
````

If `<journal>` already holds entries, read it first to understand the full context of what has been done to this environment before taking any action.

## Measurements Go to the Evidence Tier

A measurement that the report states goes to the evidence tier, not to the journal.  After a measuring step, while the cluster is up, run `report-graph.py fetch` and then `render`.  Then run `block`, and append the evidence block to `2-evidence.md`.  The Graphs section of `report.md` gives each step.  In the journal, record the commands, the dashboard and panel you rendered, and the key numbers as they happen:

````markdown
### 11:32 KeyValue baseline: evidence rendered

- **Throughput:** 24,500 op/s.
- **Latency:** p99 read 3.2ms, p99 write 1.8ms.
- **Panel:** `cassandra-overview` panel 7, 11:00:00Z to 11:30:00Z.
- **Image:** `images/throughput.png`.

```bash
report-graph.py render --grafana-url "$GRAFANA_URL" --dashboard cassandra-overview --panel 7 \
  --from 2026-05-23T11:00:00Z --to 2026-05-23T11:30:00Z --var "cluster=$CLUSTER" \
  --name throughput --docs "$DOCS" --proxy "$PROXY"
```
````

Never link to Grafana from the journal.  Every image is a render that `report-graph.py render` downloads to `docs/images/`.
