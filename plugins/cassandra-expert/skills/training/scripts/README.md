# Training Scripts

Verification scripts used to confirm factual claims in the training material
against a running Cassandra cluster. Run them when you want to be sure the
docs match reality — especially after a version bump.

## Requirements

- [uv](https://docs.astral.sh/uv/) for dependency management
- A reachable Cassandra 5.0+ cluster (anonymous or superuser access on the
  target host)

Each script declares its Python dependencies inline using [PEP 723
script metadata](https://peps.python.org/pep-0723/), so `uv run` resolves
them automatically on first invocation.

## Scripts

### `verify-sai-capabilities.py`

Confirms which column kinds SAI will and will not index. Creates a dedicated
`sai_verify` keyspace, runs `CREATE INDEX ... USING 'sai'` against five
representative cases, and reports PASS/FAIL vs. expected behaviour.

Column-kind cases:
- Single-column partition key — expected **reject**
- Clustering column — expected **accept**
- Individual column of a composite partition key — expected **accept**
- Regular non-PK column — expected **accept**
- Counter column — expected **reject**

Query-operator cases:
- Equality on an indexed text column — expected **accept**
- Range on an indexed numeric column — expected **accept**
- `LIKE` prefix match — expected **reject** (not supported by SAI in Apache Cassandra 5.0)
- Top-level same-column `OR` — expected **reject** (syntax error in Cassandra 5.0)
- Top-level cross-column `OR` — expected **reject** (syntax error in Cassandra 5.0)
- Parenthesized same-column `OR` scoped by the partition key — expected **reject** (syntax error)
- Parenthesized cross-column `OR` scoped by the partition key — expected **reject** (syntax error)

**Run:**

```bash
uv run verify-sai-capabilities.py
# or against a non-local cluster:
uv run verify-sai-capabilities.py --host 10.0.0.5 --port 9042
```

Exit code `0` if every case matches its expected outcome, non-zero otherwise.
The keyspace is dropped on completion.
