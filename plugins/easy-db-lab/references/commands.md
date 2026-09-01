# easy-db-lab Command Reference

Generated from `easy-db-lab commands`. Use this as a fallback when the binary is not available.

## How to read the listing

Everything below is generated, so it does not distinguish the two kinds of argument by shape. You
have to read the leading characters:

- A line beginning with `--` or `-` is a **flag**: `--db <<count>>` is written `--db 3`.
- A line beginning with `<<` is a **POSITIONAL**. It takes no `--`, and it goes after the flags.
  `<<name>>` is written `my-cluster`, never `--name my-cluster`.

That distinction is the single most common way a generated command fails. `init` is the one that
bites: the cluster name is the last line of a thirty-line flag list, formatted identically to the
flags above it, and `--name` reads as the obvious guess. It is not a valid option.

```bash
# Correct — name is positional, and comes after the flags
easy-db-lab init my-cluster --db 3 --app 1 --instance i3.2xlarge --up

# Wrong — fails immediately; there is no --name option
easy-db-lab init --name my-cluster --db 3 --up
```

The other positionals below take the same form: `down <<vpcId>>`, `ip <<host>>`,
`show-iam-policies <<policyName>>`, and `upload-keys <<localDir>>`.

```
easy-db-lab - Tool to create Cassandra lab environments in AWS
  aws - AWS resource discovery and management operations
    region - Get AWS region for the current cluster
    s3-bucket - Get S3 bucket name for the current cluster
    vpcs - List all easy-db-lab VPCs
  build-base - Build the base image
      --release <<release>> - Release flag
      --region, -r <<region>> - AWS region to build the image in
      --arch, -a, --cpu <<arch>> - CPU architecture
  build-cassandra - Build the Cassandra image
      --release <<release>> - Release flag
      --region, -r <<region>> - AWS region to build the image in
      --arch, -a, --cpu <<arch>> - CPU architecture
  build-image - Build both the base and Cassandra image
      --release <<release>> - Release flag
      --region, -r <<region>> - AWS region to build the image in
      --arch, -a, --cpu <<arch>> - CPU architecture
  cassandra - Cassandra cluster management and tooling operations
    cql - Execute CQL on the Cassandra cluster
        --file, -f <<file>> - Execute CQL from a local file
        <<statement>> - CQL statement to execute
    download-config - Download JVM and YAML config files
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
    list - List available versions
    nt - Execute nodetool on Cassandra nodes
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
        <<args>> - Nodetool command and arguments
    restart - Restart cassandra
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
    start - Start cassandra on all nodes via service command
        --sleep <<sleep>> - Time to sleep between starts in seconds
        --sidecar-image <<sidecarImage>> - Container image for the Cassandra sidecar DaemonSet (default: ghcr.io/apache/cassandra-sidecar:latest)
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
    stop - Stop cassandra on all nodes via service command
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
    stress - Cassandra stress testing operations on K8s
      fields - List available cassandra-easy-stress field generators
          --image <<image>> - Container image (default: ghcr.io/apache/cassandra-easy-stress:latest)
          <<stressArgs>> - Additional arguments passed to cassandra-easy-stress fields
      info - Show information about a cassandra-easy-stress workload
          --image <<image>> - Container image (default: ghcr.io/apache/cassandra-easy-stress:latest)
          <<stressArgs>> - Workload name and additional arguments passed to cassandra-easy-stress info
      list - List available cassandra-easy-stress workloads
          --image <<image>> - Container image (default: ghcr.io/apache/cassandra-easy-stress:latest)
          <<stressArgs>> - Additional arguments passed to cassandra-easy-stress list
      logs - View logs from stress jobs
          --tail <<tailLines>> - Number of lines to show from the end
          <<jobName>> (required) - Job name
      start - Start a cassandra-easy-stress job on K8s. Args are passed to cassandra-easy-stress.
          --name, -n <<jobName>> - Job name (auto-generated from workload name if not provided)
          --image <<image>> - Container image (default: ghcr.io/apache/cassandra-easy-stress:latest)
          --tags <<tags>> - Custom tags added to metrics (format: key=value,key=value)
          <<stressArgs>> - Arguments passed directly to cassandra-easy-stress (e.g., KeyValue -d 1h --threads 100)
      status - Check status of stress jobs
          --name, -n <<jobName>> - Filter by job name (partial match)
      stop - Stop and delete stress jobs
          --all <<deleteAll>> - Delete all stress jobs
          --force, -f <<force>> - Force deletion without confirmation
          <<jobName>> - Job name to stop
    update-config - Upload the cassandra.yaml fragment to all nodes and apply to cassandra.yaml
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
        --restart, -r <<restart>> - Restart cassandra after patching
        <<file>> - Patch file to upload
    use - Use a Cassandra version (3.0, 3.11, 4.0, 4.1)
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
        --java, -j <<javaVersion>> - Java Version Override, 8, 11 or 17 accepted
        <<version>> (required) - Cassandra version
    write-config - Write a new cassandra configuration patch file
        -t, --tokens <<tokens>> - Number of tokens
        <<file>> - Patch file name
  clean - Clean up generated files from the current directory
  clickhouse - ClickHouse cluster operations on K8s
    backup - Back up ClickHouse cluster data to the account S3 bucket
        --async <<async>> - Start backup in background and return immediately
        <<backupName>> (required) - Name for this backup
    init - Configure ClickHouse settings (run before clickhouse start)
        --s3-cache <<s3CacheSize>> - Size of the local S3 cache (default: 10Gi)
        --s3-cache-on-write <<s3CacheOnWrite>> - Cache data during write operations (default: true)
        --replicas-per-shard <<replicasPerShard>> - Number of replicas per shard (default: 3)
        --s3-tier-move-factor <<s3TierMoveFactor>> - Move data to S3 tier when local disk free space falls below this fraction (0.0-1.0) (default: 0.2)
    list-backups - List available ClickHouse backups in the account S3 bucket
    restore - Restore ClickHouse cluster data from a named backup in the account S3 bucket
        --async <<async>> - Start restore in background and return immediately
        <<backupName>> (required) - Name of the backup to restore from
    start - Deploy ClickHouse cluster to K8s
        --timeout <<timeoutSeconds>> - Timeout in seconds to wait for pods to be ready (default: 300)
        --skip-wait <<skipWait>> - Skip waiting for pods to be ready
        --replicas <<replicas>> - Number of ClickHouse server replicas (default: number of db nodes)
        --restore-from <<restoreFrom>> - Restore from a named backup after startup
    status - Check ClickHouse cluster status
    stop - Stop and remove ClickHouse cluster from K8s
        --force <<force>> - Force deletion without confirmation
  commands - Display all commands, subcommands, and options
  configure-aws - Configure AWS infrastructure (IAM roles, S3 bucket) for easy-db-lab
  configure-axonops - Setup / configure axon-agent for use with the Cassandra cluster
      --org <<org>> - AxonOps Organization Name
      --key <<key>> - AxonOps API Key
      --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
  down - Shut down AWS infrastructure
      --all <<teardownAll>> - Tear down all VPCs tagged with easy_cass_lab
      --packer <<teardownPacker>> - Tear down the packer infrastructure VPC
      --dry-run <<dryRun>> - Preview what would be deleted without actually deleting
      --auto-approve, -a, --yes <<autoApprove>> - Auto approve changes without confirmation prompt
      --retention-days <<retentionDays>> - Days to retain S3 data after teardown (default: 1)
      --clickhouse.backup <<clickhouseBackup>> - Back up ClickHouse data before teardown
      <<vpcId>> - Optional VPC ID to tear down a specific VPC
  exec - Execute commands on remote hosts with systemd logging
    list - List running background tools on remote hosts
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
        --type, -t <<serverType>> - Server type (cassandra, stress, control). Lists all types if not specified.
    run - Execute a command on remote hosts via systemd-run
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
        --type, -t <<serverType>> - Server type (cassandra, stress, control)
        --bg <<background>> - Run in background (returns immediately)
        --name <<unitNameOverride>> - Name for the systemd unit (auto-derived if not provided)
        -p <<parallel>> - Execute in parallel
        <<command>> (required) - Command to execute
    stop - Stop a running background tool on remote hosts
        --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
        --type, -t <<serverType>> - Server type (cassandra, stress, control). Stops on all types if not specified.
        <<name>> (required) - Name of the tool to stop (without edl-exec- prefix)
  grafana - Grafana operations
    update-config - Build and apply the full observability stack to K8s cluster
  hosts - List all hosts in the cluster
      -c <<cassandra>> - Show db nodes as a comma delimited list (deprecated: use --db)
      --db <<db>> - Show db nodes as a comma delimited list
      --app <<app>> - Show app nodes as a comma delimited list
      --private <<usePrivateIp>> - Use private IPs (default: public)
  init - Initialize this directory for easy-db-lab
      --db, --cassandra, -c <<cassandraInstances>> - Number of database instances
      --app, --stress, -s <<stressInstances>> - Number of application instances
      --up <<start>> - Start instances automatically
      --instance, -i <<instanceType>> - Instance Type
      --stress-instance, -si, --si <<stressInstanceType>> - Stress Instance Type
      --azs, --az, -z <<azs>> - Limit to specified availability zones
      --until <<until>> - Specify when the instances can be deleted
      --ami <<ami>> - AMI override
      --open <<open>> - Unrestricted SSH access
      --ebs.type <<ebsType>> - EBS Volume Type (NONE, gp2, gp3, io1, io2)
      --ebs.size <<ebsSize>> - EBS Volume Size (in GB)
      --ebs.iops <<ebsIops>> - EBS Volume IOPS (gp3 only)
      --ebs.throughput <<ebsThroughput>> - EBS Volume Throughput MB/s (gp3 only)
      --ebs.optimized <<ebsOptimized>> - Set EBS-Optimized instance
      --arch, -a, --cpu <<arch>> - CPU architecture
      --spark.enable <<enable>> - Enable Spark EMR Cluster
      --spark.master.instance.type <<masterInstanceType>> - Master Instance Type
      --spark.worker.instance.type <<workerInstanceType>> - Worker Instance Type
      --spark.worker.instance.count <<workerCount>> - Worker Instance Count
      --opensearch.enable <<enable>> - Enable AWS OpenSearch domain
      --opensearch.instance.type <<instanceType>> - OpenSearch instance type
      --opensearch.instance.count <<instanceCount>> - Number of OpenSearch data nodes
      --opensearch.version <<version>> - OpenSearch engine version
      --opensearch.ebs.size <<ebsSize>> - EBS volume size in GB per node
      --tag <<String=String>> - Tag instances (format: key=value, can be repeated)
      --clean <<clean>> - Clean existing configuration before initializing
      --vpc <<existingVpcId>> - Use an existing VPC ID instead of creating a new one
      --cidr <<cidr>> - VPC CIDR block (default: 10.0.0.0/16). Must be /20 or larger.
      <<name>> - Cluster name
  ip - Get IP address for a host by alias
      --public <<publicIp>> - Return public IP (default)
      --private <<privateIp>> - Return private IP
      <<host>> (required) - Host alias (e.g., db0, stress0)
  logs - Query logs from Victoria Logs
    backup - Backup VictoriaLogs data to S3
        --dest <<dest>> - Destination S3 URI (default: cluster S3 bucket)
    import - Import logs from cluster VictoriaLogs to an external instance
        --target <<target>> (required) - Target VictoriaLogs URL
        --query <<query>> - LogsQL query (default: all logs)
    ls - List VictoriaLogs backups in S3
    query - Query logs from Victoria Logs
        --source, -s <<source>> - Log source: emr, cassandra, clickhouse, systemd, system
        --host, -H <<host>> - Filter by hostname (db0, app0, control0)
        --unit <<unit>> - systemd unit name
        --since <<since>> - Time range: 1h, 30m, 1d (default: 1h)
        --limit, -n <<limit>> - Max lines to return (default: 100)
        --grep, -g <<grep>> - Filter logs containing text
        --query, -q <<rawQuery>> - Raw Victoria Logs query (LogsQL syntax)
  metrics - Manage VictoriaMetrics observability data
    backup - Backup VictoriaMetrics data to S3
        --dest <<dest>> - Destination S3 URI (default: cluster S3 bucket)
    import - Import metrics from cluster VictoriaMetrics to an external instance
        --target <<target>> (required) - Target VictoriaMetrics URL
        --match <<match>> - Metric selector (default: all metrics)
    ls - List VictoriaMetrics backups in S3
  opensearch - AWS OpenSearch domain operations
    start - Create an AWS OpenSearch domain
        --instance-type <<instanceType>> - OpenSearch instance type
        --instance-count <<instanceCount>> - Number of OpenSearch data nodes
        --ebs-size <<ebsSize>> - EBS volume size in GB per node
        --wait <<wait>> - Wait for domain to become active (can take 10-30 minutes)
    status - Check OpenSearch domain status
        --endpoint <<endpointOnly>> - Output only the endpoint URL (for scripting)
    stop - Delete the OpenSearch domain
        --force <<force>> - Force deletion without confirmation
  prune-amis - Prune older private AMIs
      --pattern <<pattern>> - Name pattern for AMIs to prune
      --keep <<keep>> - Number of newest AMIs to keep per architecture/type combination
      --dry-run <<dryRun>> - Show what would be deleted without actually deleting
      --type <<type>> - Filter to only prune AMIs of specific type
  repl - Start interactive REPL with full tab completion
  server - Start server for AI assistant integration
      --port, -p <<port>> - Server port (0 = any free port)
      --bind, -b <<bind>> - Address to bind the server to (default: 127.0.0.1)
      --refresh, -r <<refreshInterval>> - Status cache refresh interval in seconds (default: 30)
      --auto-shutdown <<autoShutdown>> - Shut down the server if the cluster VPC is removed
  setup-profile - Set up user profile interactively
  setup-instances - Runs setup_instance.sh on all Cassandra instances
      --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
  show-iam-policies - Display IAM policies with account ID populated
      <<policyName>> - Policy name filter (optional): ec2, iam, emr
  spark - Spark EMR cluster operations
    down - Terminate the Spark EMR cluster
    init - Provision Spark EMR cluster on existing environment
        --master.instance.type <<masterInstanceType>> - Master instance type
        --worker.instance.type <<workerInstanceType>> - Worker instance type
        --worker.instance.count <<workerCount>> - Worker instance count
    jobs - List recent Spark jobs on the cluster
        --limit <<limit>> - Maximum number of jobs to display (default: 10)
    logs - Query Spark/EMR logs from Victoria Logs
        --step-id <<stepId>> - EMR step ID (defaults to most recent job)
        --limit, -n <<limit>> - Maximum number of log lines to return (default: 100)
        --since <<since>> - Time range: 1h, 30m, 1d (default: 1d)
    status - Check status of a Spark job
        --step-id <<stepId>> - EMR step ID (defaults to most recent job)
        --verbose, -v <<verbose>> - Show detailed step information
    stop - Cancel a running or pending Spark job
        --step-id <<stepId>> - EMR step ID (defaults to most recent job)
    submit - Submit Spark job to EMR cluster
        --jar <<jarPath>> (required) - Path to JAR file (local path or s3://bucket/key)
        --main-class <<mainClass>> (required) - Main class to execute
        --args <<jobArgs>> - Arguments to pass to the Spark application
        --wait <<wait>> - Wait for job completion
        --name <<jobName>> - Job name (defaults to main class)
        --conf <<sparkConf>> - Spark configuration (key=value), can be repeated
        --env <<envVars>> - Environment variable (KEY=value), can be repeated
  status - Display full environment status
  tailscale - Tailscale VPN operations for secure cluster access
    start - Start Tailscale VPN on the control node
        --client-id <<clientId>> - Tailscale OAuth client ID
        --client-secret <<clientSecret>> - Tailscale OAuth client secret
        --tag <<tag>> - Tailscale device tag (default: tag:easy-db-lab)
    status - Show Tailscale connection status
    stop - Stop Tailscale VPN on the control node
  up - Starts instances
      --no-setup, -n <<noSetup>>
      --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
  upload-keys - Upload authorized (public) keys from the ./authorized_keys directory
      --hosts <<hostList>> - Hosts to run this on, leave blank for all hosts.
      <<localDir>> - Local directory of authorized keys
  version - Display the easy-db-lab version
```
