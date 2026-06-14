---
name: create-kit
description: Create a new easy-db-lab kit (kit.yaml + K8s manifests, metrics, dashboards, docs) for any database or workload. Detects internal (the easy-db-lab repo) vs external (your own project) mode, researches the workload, grounds the work in a per-kit TODO.md, drafts for review, and writes deliverable files only on explicit approval. Use when adding a new database or workload kit to easy-db-lab or to your own kit source.
argument-hint: "[workload name] [output path]"
user-invocable: true
---

# create-kit

Author a new easy-db-lab **kit** — a self-contained package (`kit.yaml` + manifest
templates + dashboards + docs) that installs, starts, stops, and observes a database or
workload on an easy-db-lab cluster. No Kotlin is required; kits register dynamically from
their `kit.yaml`.

This skill works for **both**:
- **Internal** kit development — inside the easy-db-lab repository (`src/main/resources/.../kits/`).
- **External** kit development — a kit that lives in your own project and is registered with
  `easy-db-lab kit source add`.

The skill detects which mode applies and adapts paths and the schema source accordingly.

## Input

The argument after `/create-kit` is the workload name (e.g. "ScyllaDB", "Kafka", "Redis").
An optional second argument is the output path. If no workload name is given, ask for one.

---

## Step 0 — Detect mode and resolve paths

Check whether the current directory is the easy-db-lab repository:

```bash
test -d src/main/resources/com/rustyrazorblade/easydblab/kits && echo INTERNAL || echo EXTERNAL
```

**Internal mode** (the path exists):
- Kit directory: `src/main/resources/com/rustyrazorblade/easydblab/kits/<name>/`
- Authoritative schema source: read the **local** files
  `docs/development/kits.md` and `src/main/kotlin/com/rustyrazorblade/easydblab/services/KitConfig.kt`.
  They are version-matched to this checkout — trust them over the cheat-sheet below.

**External mode** (the path does not exist):
- Kit directory: `./kits/<name>/` by default. If the user passed an output path, use it.
  The kit's **parent** directory (`./kits`) is what gets registered with `kit source add`.
- Authoritative schema source: `WebFetch` the published guide
  `https://rustyrazorblade.github.io/easy-db-lab/development/kits.html`
  whenever you need anything beyond the cheat-sheet below. (Repo:
  `https://github.com/rustyrazorblade/easy-db-lab/`.)

`<name>` is the kebab-case kit name. State the detected mode and resolved kit directory to
the user before proceeding.

---

## Step 1 — Research the workload

Use WebSearch and/or context7 to determine:

- The canonical Helm chart (repo URL, chart name, current stable version), or an operator/CRD
  that must be installed first (operator chart → then the custom resource).
- The primary Kubernetes resource kind the workload creates (`StatefulSet`, `Deployment`, or a
  custom CR) and the readiness condition to wait on (pod labels, conditions).
- Whether the workload is **stateful** (needs `platform-pvs` for local storage) or stateless.
- **Metrics**: does it expose a Prometheus endpoint? Port and path? Or is it JVM-based
  (OTel/Pyroscope java agent), or does the chart ship its own OTLP pipeline (`helm-native`)?
- **Endpoints / wire protocols**: what ports clients connect on (HTTP, JDBC, native, CQL,
  PostgreSQL/MySQL wire), and whether it exposes a SQL interface (declare the `sql` capability
  so bench kits like sysbench can target it).
- **JVM?**: if yes, plan Pyroscope java-agent injection in the `start` phase.
- **Integration with existing kits**: does this workload need a backing store or data source
  another kit provides (e.g. Temporal needs PostgreSQL/Cassandra; Trino/Presto register catalogs
  for ClickHouse/Cassandra/TiDB)? Or is it a bench/consumer kit that targets a running database?
  Check `easy-db-lab kit list` / the kits dir for what already exists, then pick a wiring
  mechanism (see *Integrating with other kits* below).

Summarize findings in 3–5 bullets — including the recommended `metrics.type`, whether
Pyroscope injection is needed, and any cross-kit integration — before grounding the work.

### Integrating with other kits

Three mechanisms wire kits together — pick by the relationship:

- **kit-ref arg (`--target`)** — a kit that *targets* a user-chosen running kit (bench/consumer
  kits). Declare `{ flag: --target, variable: TARGET, type: kit-ref, capability: sql }`. At
  start, `KitEndpointResolver` reads the target kit's endpoints and injects `TARGET_*` env vars
  (`TARGET_PG_HOST/PORT/USER/DATABASE`, `TARGET_JDBC_URL`, `TARGET_MYSQL_HOST`, …) into every
  phase; the installed dir becomes `<kit>-<target>`. Reference: `sysbench`.
- **Hooks (`post-workload-start` / `post-workload-stop`)** — a kit that *reacts* when another
  kit starts or stops (e.g. registering a connector/catalog). Optionally scope with
  `workloads: [postgres, clickhouse]` (the YAML field is `workloads`, not `kits`); omit to fire
  for any kit. Reference: Trino's `bin/update-catalogs.sh`, which re-registers catalogs after
  ClickHouse/Cassandra/TiDB start.
- **In-cluster service DNS** — a hard dependency on another kit's service: reference its stable
  cluster DNS directly in a manifest/values template
  (e.g. `clickhouse-clickhouse.default.svc.cluster.local:8123`). Use when the backing kit is
  assumed present.

For a SQL database others should be able to target, declare the `sql` capability so kit-ref
consumers can find it.

#### Reading another kit's values into a configmap or manifest

Typed-step string fields are substituted with the **`${VAR}`** pattern against the runtime
variable set (the same set `shell:` steps receive as environment variables). This includes
`configmap` `data:` values, `label` values, `exec` command/namespace/pod, and `manifest` bodies
when the step sets `interpolate: true`. So to write another kit's connection info into a
configmap (e.g. you need `THE_POSTGRES_ENDPOINT` for your own reasons):

1. Declare a `kit-ref` arg so the framework injects that target's `TARGET_*` vars:

```yaml
args:
  - flag: --postgres
    variable: POSTGRES
    type: kit-ref
    capability: sql
    description: "Postgres kit to read connection info from"
    required: true
```

2. Reference the injected `TARGET_*` var with **`${VAR}`** in the configmap data:

```yaml
start:
  - type: configmap
    name: my-app-config
    namespace: default
    data:
      THE_POSTGRES_ENDPOINT: "${TARGET_PG_HOST}:${TARGET_PG_PORT}"
```

`TARGET_PG_HOST` / `TARGET_PG_PORT` come from the postgres kit's `postgresql` endpoint (see the
`TARGET_*` variables under the kit-ref bullet above). Use `${VAR}`, **not** `$VAR` — a bare
`$VAR` is not substituted in configmap/manifest/typed-step fields (it only works inside `shell:`
scripts, where vars arrive as real env vars). If the value need not be user-selectable, skip the
arg and hardcode the target kit's in-cluster service DNS instead, e.g.
`"postgres-rw.default.svc.cluster.local:5432"`.

---

## Step 2 — Ground the work in a TODO.md

Create the kit directory and write a **`TODO.md`** into it. This is a scratch working file
that keeps the work on-plan across context resets — tick items off as you complete them.

```bash
mkdir -p <kit-dir>
```

Write `<kit-dir>/TODO.md` tailored to this kit (adjust phases to what the workload needs):

```markdown
# create-kit: <name> — progress

Mode: <internal|external>   Kit dir: <kit-dir>

## Research
- [x] Workload researched (chart/operator, readiness, metrics, endpoints)
- [x] Integration with existing kits assessed (kit-ref / hooks / service DNS)

## kit.yaml
- [ ] Draft kit.yaml presented and approved
- [ ] kit.yaml written

## Manifests
- [ ] <name>.yaml.template (primary resource / CR) written
- [ ] nodeport-service.yaml.template written (if clients connect from outside the pod network)
- [ ] hostPort added for scrape metrics port (if metrics.type: scrape)
- [ ] Pyroscope java-agent patch added to start phase (if JVM)

## Metrics & dashboards   (requires a live cluster)
- [ ] Installed + started on a cluster; metrics flowing to VictoriaMetrics
- [ ] metrics-catalog.json exported (export-workload-metrics <name>)
- [ ] METRICS.md authored (every metric name present in the catalog)
- [ ] dashboards/<name>.json authored (uid <name>-kit, cluster=~"$cluster", VictoriaMetrics)

## Docs
- [ ] README.md.template written
- [ ] CLAUDE.md (developer notes) written

## Validate & register
- [ ] kit list shows the kit            (external: after `kit source add`)
- [ ] install → start → stop verified on a live cluster
- [ ] dashboard loads in Grafana with real data
- [ ] Decide whether to delete this TODO.md
```

Writing `TODO.md` is a process artifact and does not require the approval gate. The
**deliverable** files (`kit.yaml`, templates, dashboards, docs) still require approval — see Step 3.

---

## Step 3 — Draft kit.yaml and refine

Using the research and the **Schema cheat-sheet** below (and the authoritative source for your
mode — see Step 0), draft a `kit.yaml`. Present it to the user as a code block and briefly
explain each block. **Do not write any deliverable files yet.**

Copy the closest existing kit as a structural model — e.g. `clickhouse` (operator + CR +
keeper + nodeport + backup/restore) or `postgres` (CNPG operator + extensions). In internal
mode, read it from `src/main/resources/.../kits/<kit>/kit.yaml`.

Refine interactively: accept feedback, update the draft, re-present. Repeat until the user
explicitly approves. "Looks good" / "go ahead" counts as approval; "what do you think?" does not.

---

## Step 4 — Write kit.yaml and manifest templates

Once approved, write:

- `<kit-dir>/kit.yaml`
- A `<resource>.yaml.template` for every `type: manifest` step, built from the workload's CRD
  schema with `__VAR__` substitutions for configurable values.
- A `nodeport-service.yaml.template` if external clients (or bench kits) connect to a declared
  endpoint port.

Requirements:
- **`hostPort`** — if `metrics.type: scrape`, the metrics port must be exposed via `hostPort`
  in the pod spec (or a NodePort the OTel DaemonSet can reach), or scraping fails. The OTel
  DaemonSet runs with `hostNetwork: true`.
- **Pyroscope (JVM kits)** — inject `JAVA_TOOL_OPTIONS` via a `kubectl patch` in the `start`
  phase, mounting `/usr/local/pyroscope` as a `hostPath`. Use `${CONTROL_HOST_PRIVATE}` and
  `${CLUSTER_NAME}` as **runtime env vars** (`$VAR` in the shell), not `__VAR__` substitutions.
  See the Profiling section of the kit guide for the exact patch.

Tick the matching `TODO.md` boxes after writing.

---

## Step 5 — Metrics artifacts (scrape kits — requires a live cluster)

These are authored once from real data on a running cluster and committed alongside the kit.
**Write everything you can offline, then pause and hand off** the live-cluster steps with a
clear checklist rather than provisioning a cluster yourself.

1. Install and start the kit on a cluster so metrics flow to VictoriaMetrics.
2. From the cluster working directory (where `env.sh` and the kubeconfig live), run
   `export-workload-metrics <name>` → `<name>/metrics-catalog.json` (workload name, timestamp,
   series with names + labels). The script ships with this plugin (`bin/export-workload-metrics`);
   it queries VictoriaMetrics for `{job="<name>"}`, so the kit must be running and scraping first.
3. Author `METRICS.md` — a markdown table of the genuinely useful metrics. **Every metric name
   must appear in `metrics-catalog.json`.**
4. Author `dashboards/<name>.json` — built from the names in `METRICS.md`:
   - `"uid": "<name>-kit"` (idempotent re-installs)
   - a `cluster` template variable; scope panels with `{cluster=~"$cluster",job="<name>"}`
   - datasource `{ "type": "prometheus", "uid": "VictoriaMetrics" }`, `"tags": ["<name>","kit"]`

The dashboard is auto-installed when `start` completes (any `.json` in `dashboards/`).
Metrics registration (the OTel scrape job) is **automatic** for `metrics.type: scrape` — do not
add `configmap` or sync steps for it.

---

## Step 6 — Docs

- `README.md.template` — connection info, lifecycle commands, integrations. Use `__VAR__`
  substitution (e.g. `__CLUSTER_NAME__`, `__STORAGE_SIZE__`, `__REGION__`). Model it on
  `postgres/README.md.template`.
- `CLAUDE.md` — developer notes for anyone maintaining this kit (non-obvious decisions, image
  quirks, operator gotchas). Model it on `postgres/CLAUDE.md`.

In **internal mode**, if the change affects the kit schema or adds a notable pattern, update
`docs/development/kits.md`. External kits don't touch the easy-db-lab docs.

---

## Step 7 — Validate and register

**Internal mode:**
```bash
easy-db-lab kit list            # the kit appears
easy-db-lab kit install <name>
easy-db-lab <name> start        # on a live cluster
easy-db-lab <name> stop
```

**External mode** — register the parent kits directory first (analogous to `git remote add`):
```bash
easy-db-lab kit source add <label> <absolute-path-to-kits-parent-dir>
easy-db-lab kit list            # the kit now appears
easy-db-lab kit install <name>
easy-db-lab <name> start
```

Verify the dashboard loads in Grafana with real data. Tick the remaining `TODO.md` boxes,
then **offer to delete `TODO.md`** (it is a scratch file, not a kit artifact).

---

## Schema cheat-sheet

Orientation only. For the full, current schema use your mode's authoritative source (Step 0):
local `docs/development/kits.md` + `KitConfig.kt` (internal) or the published guide (external).

**Top-level `kit.yaml` fields:** `name`, `description`, `version`, `type` (`db`|`app`),
`collision-check` (bool), `metrics` (list), `runtime`, `endpoints` (list), `args` (list),
`capabilities` (list), `dashboards` (list, optional — auto-discovered otherwise), `hooks`, and
the phase step-lists `install` / `start` / `stop` / `uninstall` / `backup` / `restore`.

**metrics** (list):
- `{ type: scrape, port: <int>, path: /metrics }`
- `{ type: java-agent, service-name: <name> }`
- `{ type: helm-native }`

**runtime:** `{ type: helm|deployment|statefulset|pods, release|name|selector, namespace }`

**endpoints[]:** `{ name, node-type: app|db, port, type: http|https|jdbc|native|cql|postgresql|mysql, scheme?, path?, database? }`

**args[]:** `{ flag, variable, description, type: string|int|float|boolean|kit-ref|extension, required?, default?, capability? }`
The version flag is **always** `--version` (never `--<kit>-version`). A `type: kit-ref` arg
(e.g. `--target`, `capability: sql`) makes the framework inject the target kit's endpoints as
`TARGET_*` env vars (`TARGET_PG_HOST/PORT/USER/DATABASE`, `TARGET_JDBC_URL`, `TARGET_MYSQL_*`,
`TARGET_HTTP_URL`) into every phase, and names the installed dir `<kit>-<target>`.

**capabilities[]:** `{ type: sql, user, driver-class? }` — registers a `<kit> sql` command and
makes the kit targetable by bench kits.

**hooks:** `{ post-workload-start: { script, workloads? }, post-workload-stop: { script, workloads? } }` —
fire a script when another kit starts/stops, so this kit can react (e.g. register a catalog).
Scope to specific kits with `workloads: [...]` (field is `workloads`, not `kits`); omit to fire
for any. See *Integrating with other kits* (Step 1).

**Step types** (same set in every phase): `helm-repo`, `helm`, `helm-uninstall`, `namespace`,
`manifest`, `manifest-url`, `kustomize`, `wait`, `delete`, `platform-pvs`, `platform-pvs-delete`,
`configmap`, `label`, `exec`, `shell`. Prefer typed steps; use `shell` only for readiness
checks a `wait` step can't express (e.g. `kubectl wait` on a label selector).

**Three substitution contexts — do not mix them up:**
- `__VAR__` — in `.yaml.template` / `README.md.template` files (TemplateService, applied at
  `kit install` when templates are copied to the working dir).
- `${VAR}` — framework substitution at step-execution time. Applies to `kit.yaml` `default:`
  fields **and** typed-step string fields: `configmap` `data`, `label` values, `exec`
  command/namespace/pod, `manifest` template paths, and `manifest` bodies when `interpolate: true`.
- `$VAR` — in `shell:` step scripts only. The script text is **not** pre-substituted; the
  variables arrive as real environment variables, so ordinary shell `$VAR` expansion applies.

The `manifest` step substitutes `${VAR}` in the file body only when `interpolate: true`
(default false); a plain `.yaml.template` manifest gets `__VAR__` at install time instead.

**Common runtime variables:** `CLUSTER_NAME`, `KUBECONFIG`, `CONTROL_HOST_PRIVATE`,
`DB_NODE_COUNT`, `APP_NODE_COUNT`, `DB_NODE_IPS`, `APP_NODE_IPS`, `STORAGE_SIZE`,
`STORAGE_CLASS_WFC`, `REGION`, `ACCOUNT_BUCKET`, `KIT_NAME`, `BACKUP_NAME` (backup/restore only),
plus every arg `variable`.

---

## Guardrails

- **Never write deliverable files before explicit approval.** `TODO.md` is the only file
  written before approval (it's a process artifact).
- **Use typed steps; avoid `shell`** except for label-selector readiness waits.
- **Metrics registration is automatic** for `metrics.type: scrape` — never add `configmap` or
  OTel-sync steps; the runtime creates/removes the scrape job on `start`/`stop`.
- **Always add `hostPort`** (or a reachable NodePort) for scrape metrics ports.
- **Kit shell scripts that create K8s pods** must use unique `pod-name-$(date +%s)` names,
  label every pod `easydblab/kit=${KIT_NAME}` and `easydblab/role=<role>`, and clean up in
  `stop` by label selector — never by fixed name. (Reference: the sysbench kit.)
- **Use `jq`, never Python, for JSON in shell scripts.**
- **Large `storageSize` defaults (e.g. `10Ti`) are intentional** — LPV provisioner ignores PVC
  size. Never flag them as wasteful.
- **Keep `args` minimal** — only flags a user would actually tune at install time.
- **Verify the drafted `kit.yaml` is parseable** before reporting completion — trace it against
  the schema for typos in step types or missing required fields.
