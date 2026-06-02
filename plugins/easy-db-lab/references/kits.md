# Kits

Kits are databases and applications that can be installed into an easy-db-lab cluster. Each kit adds its own subcommands for starting, stopping, and managing the installed software.

## Contents

- [Discovering and Installing Kits](#discovering-and-installing-kits)
- [Inspecting a Kit](#inspecting-a-kit)
- [After Installation](#after-installation)
- [Accessing Kit Services](#accessing-kit-services)
- [Cassandra](#cassandra)
- [Kit Metrics](#kit-metrics)
- [Kit Reference](#kit-reference)
  - [Presto](#presto)

## Discovering and Installing Kits

```bash
# List available kits
easy-db-lab kit list

# Install a kit by name
easy-db-lab kit install <name>
```

Always run `easy-db-lab kit list` to see what is available — do not guess kit names.

If the user asks to install something that is **not** in the list, stop and ask them what they mean. Do not guess, do not try alternative approaches, and **never run `docker` commands**. The kit system is the only supported installation mechanism.

## Inspecting a Kit

Before or after installing a kit, use `kit info` to see what it does, what ports it exposes, and any other relevant details:

```bash
easy-db-lab kit info <name>
```

## After Installation

Once a kit is installed, it provides its own subcommands under `easy-db-lab <kit-name>`. Run `easy-db-lab commands` after installation to see the full set of available subcommands for the installed kit.

## Accessing Kit Services

Tailscale is installed and active on every cluster. This gives direct access to private node IPs — no `kubectl port-forward` needed. Use `kit info` to find the ports a kit exposes, then connect directly via the node's private IP.

## Cassandra

Cassandra is a built-in database and does not use the kit system. It is managed via `easy-db-lab cassandra`. See `cassandra.md` for the full workflow.

## Kit Metrics

Each kit should include a `METRICS.md` file describing the metrics it exposes. When planning or running tests, load the relevant kit's `METRICS.md` to understand what is available before querying.

Metrics are collected by VictoriaMetrics and can be queried using its HTTP API or through Grafana. Use `kit info <name>` to locate the metrics documentation for a specific kit.

---

## Kit Reference

### Presto

Presto is a distributed SQL query engine. If Cassandra is already running when Presto is installed, the kit automatically configures Cassandra as a catalog — no manual catalog setup required. To take advantage of this, start Cassandra before installing Presto.

**Querying:** Use the Presto REST API to submit and retrieve query results — do not attempt to use the Presto CLI. Use `kit info presto` to find the HTTP port, then connect via the node's private IP over Tailscale.
