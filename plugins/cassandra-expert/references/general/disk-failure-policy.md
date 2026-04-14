# Disk Failure Policy

Controls how Cassandra reacts to unrecoverable errors on data directories.

```yaml
# cassandra.yaml
disk_failure_policy: stop
```

## Options

| Option | Behavior |
|--------|----------|
| `die` | JVM exits immediately — clear signal, easy to alert on |
| `stop` | Stops CQL/gossip, JVM stays up — prevents restart loops on permanent disk failure |
| `best_effort` | Disables failing disk, continues on others — only viable with multiple data directories |
| `ignore` | Logs and continues — **never use**, risks silent data corruption |

## Recommendation

Use `stop` when systemd or another process supervisor auto-restarts Cassandra — this prevents an infinite restart loop on a permanently failed disk while still making the node clearly unavailable.

Use `die` when there is no auto-restart configured — the process exits and monitoring detects its absence.

**Never use `ignore`** — continuing after a disk failure risks serving corrupt data or silently losing writes.

Ensure this setting is consistent across all nodes.

## See Also

- `commitlog.md` — separate `commit_failure_policy` for commitlog write failures
- `cluster-configuration.md` — cassandra.yaml consistency across nodes
