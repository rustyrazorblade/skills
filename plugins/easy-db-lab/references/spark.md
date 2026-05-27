# Spark Workflow

Spark runs on AWS EMR and can be provisioned on top of an existing easy-db-lab environment, or enabled at init time with `--spark.enable`.

## Provision

```bash
# Provision Spark EMR cluster on existing environment
easy-db-lab spark init

# Specify instance types and worker count
easy-db-lab spark init \
  --master.instance.type m5.xlarge \
  --worker.instance.type m5.2xlarge \
  --worker.instance.count 3
```

Or enable at `easy-db-lab init` time:
```bash
easy-db-lab init my-cluster --db 3 --app 1 --instance m5.2xlarge \
  --spark.enable \
  --spark.master.instance.type m5.xlarge \
  --spark.worker.instance.type m5.2xlarge \
  --spark.worker.instance.count 3
```

## Submit Jobs

```bash
# Submit a job (--jar and --main-class are required)
easy-db-lab spark submit \
  --jar s3://bucket/my-job.jar \
  --main-class com.example.Main

# Pass arguments to the application
easy-db-lab spark submit \
  --jar s3://bucket/my-job.jar \
  --main-class com.example.Main \
  --args "--input s3://bucket/data --output s3://bucket/results"

# Wait for job completion before returning
easy-db-lab spark submit \
  --jar my-job.jar \
  --main-class com.example.Main \
  --wait

# Name the job, add Spark config and env vars
easy-db-lab spark submit \
  --jar my-job.jar \
  --main-class com.example.Main \
  --name my-job \
  --conf spark.executor.memory=4g \
  --conf spark.executor.cores=2 \
  --env AWS_REGION=us-east-1
```

## Monitor and Manage Jobs

```bash
# List recent jobs (default: 10)
easy-db-lab spark jobs
easy-db-lab spark jobs --limit 20

# Check status of the most recent job
easy-db-lab spark status

# Check status of a specific step
easy-db-lab spark status --step-id s-XXXXXXXXXXXX

# Verbose output (equivalent to aws emr describe-step)
easy-db-lab spark status --step-id s-XXXXXXXXXXXX --verbose

# View logs (defaults to most recent job, last 1d)
easy-db-lab spark logs
easy-db-lab spark logs --step-id s-XXXXXXXXXXXX --limit 200 --since 6h

# Cancel the most recent running or pending job
easy-db-lab spark stop

# Cancel a specific step
easy-db-lab spark stop --step-id s-XXXXXXXXXXXX
```

## Tear Down

```bash
easy-db-lab spark down
```
