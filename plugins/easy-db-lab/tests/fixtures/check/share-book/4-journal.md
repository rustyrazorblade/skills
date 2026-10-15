# Lab Journal

## 2026-10-01 10:00 UTC: open the SOCKS tunnel

Opened an SSH SOCKS tunnel to 10.0.1.15 in vpc-0abc1234def567890, on port 1080.

Node db0 is ip-10-0-1-15.ec2.internal in account 123456789012, subnet-0abc1234, sg-0abc1234, igw-0abc1234, and i-0abc1234def567890.

```bash
export AWS_PROFILE=AccountUser-417835013894
PROXY=socks5h://127.0.0.1:1080
$EDB status
"${EDB}" down --auto-approve
$EDB_BASELINE report upload
${EDB_CANDIDATE} status
```

## 2026-10-01 10:05 UTC: keep the measurements

- **Version:** Cassandra 5.0.9 on db0.
- **Control node:** control0 10.0.1.20.
- **Cluster label:** `report-ab-896195de-19a1-43fe-b315-751612345678`.
- **Load on disk:** 214748364800.0 bytes, from `$EDB status`.
- **Docs:** /Users/someone/lab/docs.

## 2026-10-01 10:10 UTC: probe with credentials

- **Upload:** the report went to s3://easy-db-lab-d779bb37-1234-4abc-9def-0123456789ab/clusters/lab/docs.
- **Bucket:** easy-db-lab-d779bb37-1234-4abc-9def-0123456789ab.

```bash
cqlsh -u cassandra -p s3cr3t-cql 10.0.1.15
curl -u admin:s3cr3t-curl http://control0:3000/api/health
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
GF_SECURITY_ADMIN_PASSWORD=s3cr3t-gf
```
