# Lab Journal

## 2026-10-13 — arms122: small memtable heap space, cross-cluster A/B

### 19:13 Coordinator: discovery, plans, and scaffold

Unattended run, with a stated shutdown intent.

- **SSO:** valid.  No running instances; no `arms122-*` VPC.
- **Upload support:** `.md` only; no images or CSV.
- **Scaffold:** exit 0.  `LAYOUT=arms`, both arms unprovisioned.

**Next:** baseline first, then candidate as the render arm.

```bash
setup-cluster.sh "$TEST_DIR" "$BIN" --name "Small memtable heap space (12.2)" --plan arms122-template.md \
  --arm baseline=arms122-baseline.md --arm candidate=arms122-candidate.md
```

### 21:02 Coordinator: overlay render

The write p99 overlay render failed.

- **Result: failed** with `cannot reach Grafana: ConnectTimeout`.
- **Tunnel:** dead; `status` restarted it on a new port.

```bash
report-graph.py render --grafana-url "$GRAFANA_URL" --dashboard ab-comparison --panel 1003 \
  --name write-p99-overlay --docs "$DOCS" --proxy "$PROXY"
```

### 21:40 Coordinator: the check

- **Check:** 5 passes; the final pass is clean.  Details are in `5-issues.md`.
