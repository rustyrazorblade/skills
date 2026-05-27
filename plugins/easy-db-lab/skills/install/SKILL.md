---
name: install
description: Install and operate easy-db-lab kits — databases, analytics engines, query engines, and apps. Each kit provides start, stop, backup, and restore commands.
argument-hint: [kit name or "list" to see available kits]
user-invocable: true
---

# Easy DB Lab — Install

You are helping the user install and operate easy-db-lab kits.

## Environment

Load `../../references/environment.md` for details on the AWS environment, k3s, observability stack, SSH access, and the `source env.sh` requirement after `up`.

## Session Log

Load `../../references/history.md` for instructions on maintaining `history.md`. Read `history.md` if it exists before taking any action.

## First Step — Get Current Command Surface

```bash
easy-db-lab commands
```

Use this to confirm the exact flags and subcommands for `install` and any installed kits. The interface may have changed since this skill was written.

## What Is a Kit?

A kit is an installable component that easy-db-lab can deploy and manage. Kits can be:

- **Databases** — e.g. Cassandra, ClickHouse, PostgreSQL
- **Analytics engines** — e.g. Spark
- **Query engines** — e.g. Trino, Presto
- **Apps** — workload generators, tools, or other applications

## Installing a Kit

```bash
# List available kits
easy-db-lab install --list

# Install a kit
easy-db-lab install <kit>
```

If the user doesn't know which kit they want, show them the list from `easy-db-lab install --list` and ask.

## Operating an Installed Kit

Once a kit is installed, it provides its own subcommands:

```bash
easy-db-lab <kit> start
easy-db-lab <kit> stop
easy-db-lab <kit> backup
easy-db-lab <kit> restore
```

Always run `easy-db-lab commands` first to see the exact flags each kit's subcommands accept — they vary by kit.

## Workflow

1. Confirm the environment is up (`state.json` exists, `easy-db-lab status` shows nodes ready)
2. List available kits if the user is unsure what to install
3. Install the kit
4. Start the kit
5. Verify it's running via `easy-db-lab <kit> status` (if available) or `easy-db-lab status`

## Guidance

- A kit may depend on the cluster being fully up before it can be installed — check `easy-db-lab status` if install fails.
- Backup and restore behavior varies by kit — always check the flags from `easy-db-lab commands` before running them.
