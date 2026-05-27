---
name: provision
description: Provision a new easy-db-lab environment — single DC or multi-DC. Handles infrastructure only: instances, networking, VPC peering, and security groups.
argument-hint: [cluster name and options — e.g. "3 node cluster", "2 DCs, 3 nodes each"]
user-invocable: true
---

# Easy DB Lab — Provision

You are provisioning the AWS infrastructure for an easy-db-lab environment. This skill covers instances and networking only — database setup and configuration is done separately with `/easy-db-lab:explore`.

## Environment

Load `../../references/environment.md` for details on the AWS environment, k3s, SSH access, and the `source env.sh` requirement after `up`.

## Session Log

Load `../../references/history.md` for instructions on maintaining `history.md`. Read `history.md` if it exists before taking any action.

## Discover the Command Surface First

Before building any `easy-db-lab` command, run:

```bash
easy-db-lab commands
```

Use this output as the authoritative source for flag names, subcommand structure, and available options. Never guess flags — if a flag isn't in the output of `easy-db-lab commands`, do not use it.

## Step 1 — Determine Topology

Ask the user:
- **Single DC or multi-DC?**
- **How many DCs?** (if multi-DC)
- **Cluster/DC name(s)** — used to tag AWS resources
- **Number of db nodes** (`--db`) — no default, ask the user
- **Number of app nodes** (`--app`) — needed for stress testing; 0 if not needed
- **Expiry** (`--until`) — optional
- **Availability zones** (`--azs`) — optional

For multi-DC, each DC lives in its own subdirectory (e.g. `dc1/`, `dc2/`). All `easy-db-lab` commands for a DC must be run from its directory.

For **multi-DC only**, assign non-overlapping CIDR blocks (must be /20 or larger (e.g. /20, /19, /16)):
- dc1: `10.0.0.0/16` (default)
- dc2: `10.1.0.0/16`
- dc3: `10.2.0.0/16`
- etc.

### Instance Selection

If the user has not specified instance types, guide them through three choices — one at a time.

**1. Architecture**

```
1) x86_64
2) arm64 (Graviton — better price/performance)
```

**2. Storage**

```
1) Local NVMe (instance storage) — lower latency, no extra cost, lost on stop
2) EBS — persistent, flexible size/IOPS, small added cost
```

If the user chooses EBS, ask which volume type (default: gp3):
```
1) gp3 (recommended) — configurable IOPS and throughput, best value
2) io2 — provisioned IOPS SSD, for latency-sensitive workloads
```

Then ask:
- **Size** (GB) — no default, ask the user
- **IOPS** — only for gp3 and io2; gp3 default is 3000, io2 ask the user
- **Throughput** (MB/s) — only for gp3; default 125 MB/s

**3. Size**

| # | Size   | x86 / Local NVMe  | x86 / EBS      | arm64 / Local NVMe | arm64 / EBS    |
|---|--------|-------------------|----------------|--------------------|----------------|
| 1 | Small  | i4i.xlarge        | m5.xlarge      | im4gn.xlarge       | m7g.xlarge     |
| 2 | Medium | i4i.2xlarge       | m5.2xlarge     | im4gn.2xlarge      | m7g.2xlarge    |
| 3 | Large  | i4i.4xlarge       | m5.4xlarge     | im4gn.4xlarge      | m7g.4xlarge    |
| 4 | Other  | (user specifies)  | (user specifies)| (user specifies)  | (user specifies)|

For EBS: `--ebs.iops` and `--ebs.throughput` apply to gp3, io1, and io2. `--ebs.throughput` applies to gp3 only.

For app/stress nodes, ask if they want a different instance type or the same as db nodes.

## Step 2 — Check Existing State

For each DC directory, check whether it has already been provisioned:

```bash
ls <dc-dir>/state.json 2>/dev/null && echo EXISTS || echo EMPTY
```

If `state.json` exists in any DC directory, run `easy-db-lab status` from that directory and show the user before proceeding. Do not re-provision without explicit confirmation.

## Step 3 — Init and Up Each DC

For multi-DC, init and up all DCs in parallel — each in its own shell:

```bash
(mkdir -p dc1 && cd dc1 && easy-db-lab init dc1 --db 3 --app 1 --instance m5.2xlarge --cidr 10.0.0.0/16 --up) &
(mkdir -p dc2 && cd dc2 && easy-db-lab init dc2 --db 3 --app 1 --instance m5.2xlarge --cidr 10.1.0.0/16 --up) &
wait
```

Then source `env.sh` in each DC directory after all are up:

```bash
cd dc1 && source env.sh && cd ..
cd dc2 && source env.sh && cd ..
```

For single DC, no `--cidr` is required and no subdirectory is needed unless the user prefers it.

## Step 4 — VPC Peering (multi-DC only)

Run `easy-db-lab status` in each DC directory — the output contains the VPC ID, node IPs, region, and everything else needed.

```bash
cd dc1 && easy-db-lab status && cd ..
cd dc2 && easy-db-lab status && cd ..
```

Create and accept the peering connection:

```bash
REGION=$(cd dc1 && easy-db-lab aws region)

PEER_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id <dc1-vpc-id> \
  --peer-vpc-id <dc2-vpc-id> \
  --region $REGION \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)

aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEER_ID \
  --region $REGION
```

For 3+ DCs, peer each pair: dc1↔dc2, dc1↔dc3, dc2↔dc3, etc.

Add routes in each VPC's route tables:

```bash
aws ec2 create-route \
  --route-table-id <dc1-route-table-id> \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id $PEER_ID \
  --region $REGION

aws ec2 create-route \
  --route-table-id <dc2-route-table-id> \
  --destination-cidr-block 10.0.0.0/16 \
  --vpc-peering-connection-id $PEER_ID \
  --region $REGION
```

Use `aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<vpc-id>"` to find route table IDs.

## Step 5 — Update Security Groups (multi-DC only)

```bash
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --region $REGION

aws ec2 authorize-security-group-ingress \
  --group-id <dc1-sg-id> \
  --protocol -1 \
  --cidr 10.1.0.0/16 \
  --region $REGION

aws ec2 authorize-security-group-ingress \
  --group-id <dc2-sg-id> \
  --protocol -1 \
  --cidr 10.0.0.0/16 \
  --region $REGION
```

Repeat for each DC pair.

## Step 6 — Verify

Run `easy-db-lab status` from each DC directory and confirm all nodes are reachable:

```bash
cd dc1 && easy-db-lab status && cd ..
cd dc2 && easy-db-lab status && cd ..
```

Infrastructure is ready. Use `/easy-db-lab:explore` for database setup and configuration.
