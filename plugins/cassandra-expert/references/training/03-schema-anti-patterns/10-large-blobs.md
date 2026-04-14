# Topic: Large Blob Storage

## Objective
Understand why Cassandra is the wrong place to store large binary objects, and how to use object storage correctly alongside Cassandra.

## Why This Matters
Storing large files (images, videos, documents, backups) in Cassandra causes severe performance problems — compaction takes longer, streaming slows down, and reads saturate disk I/O. Object stores (S3, GCS, Azure Blob) are purpose-built for this use case and do it orders of magnitude better. Cassandra should store the reference, not the data.

---

## Concept

### Why Large Blobs Hurt Cassandra

Cassandra is optimized for small-to-medium sized rows (bytes to kilobytes). Storing large blobs causes:

- **Compaction problems**: merging SSTables with large blobs is extremely slow and disk-intensive
- **Streaming bottlenecks**: bootstrap and repair must stream the blobs along with all other data — large blobs extend streaming time dramatically. (Streaming, bootstrap, and repair aren't covered in detail in this training — see the [Streaming](../../general/streaming.md) and [Repair](../../general/repair.md) references. The short version: when a new node joins the cluster or repair runs, nodes copy data to each other as SSTable streams; the more bytes per SSTable, the longer the stream.)
- **Read latency**: reading a large blob deserializes it entirely into JVM heap — GC pressure, latency spikes
- **Network overhead**: replication sends the full blob to all replicas on every write
- **Heap pressure**: Cassandra's read path keeps data in off-heap caches, but large blobs overflow into heap

### What "Large" Means

As a rule of thumb:
- **< 1KB**: fine in Cassandra
- **1KB – 1MB**: acceptable with care; watch compaction and streaming impact
- **> 1MB**: use object storage instead

### The Correct Pattern: Reference + Object Storage

Store the data in an object store. Store the reference (URL or key) in Cassandra alongside metadata about the object.

```
Write path:
  1. Upload file to S3/GCS → get object URL/key
  2. Write metadata + URL to Cassandra

Read path:
  1. Query Cassandra for metadata + URL
  2. Fetch file directly from S3/GCS (or via CDN)
```

This gives you:
- Cassandra handles what it's good at: fast metadata lookups
- Object storage handles what it's good at: large binary data, CDN integration, lifecycle policies
- Reads go directly to the CDN/object store — Cassandra is not in the read hot path for large data

### Object Storage Options

| Provider | Service |
|----------|---------|
| AWS | S3 |
| Google Cloud | Cloud Storage (GCS) |
| Azure | Blob Storage |
| Self-hosted | MinIO (S3-compatible) |

---

## Examples

### Anti-pattern: storing images in Cassandra
```sql
-- ANTI-PATTERN: storing the image bytes directly
CREATE TABLE product_images (
    product_id uuid,
    image_id   uuid,
    image_data blob,   -- could be megabytes per row
    PRIMARY KEY (product_id, image_id)
);
```

### Correct: reference pattern
```sql
-- Store metadata and URL, not the data
CREATE TABLE product_images (
    product_id   uuid,
    image_id     uuid,
    storage_url  text,      -- 's3://my-bucket/products/abc/main.jpg'
    content_type text,      -- 'image/jpeg'
    size_bytes   bigint,
    uploaded_at  timestamp,
    PRIMARY KEY (product_id, image_id)
) WITH CLUSTERING ORDER BY (image_id ASC);
```

```python
import boto3

s3 = boto3.client('s3')

insert_image = session.prepare("""
    INSERT INTO product_images (product_id, image_id, storage_url, content_type, size_bytes, uploaded_at)
    VALUES (?, ?, ?, ?, ?, toTimestamp(now()))
""")

def upload_product_image(product_id, image_id, file_bytes, content_type):
    # Step 1: upload to S3
    key = f"products/{product_id}/{image_id}"
    s3.put_object(Bucket='my-bucket', Key=key, Body=file_bytes, ContentType=content_type)
    storage_url = f"s3://my-bucket/{key}"

    # Step 2: store reference in Cassandra
    session.execute(insert_image, [
        product_id, image_id, storage_url, content_type, len(file_bytes)
    ])
```

---

## Pulse Check

> A developer stores user-uploaded profile photos as `blob` columns in the `users` table. Photos average 500KB each and the platform has 10 million users.
>
> **What is the total data stored in this column, and why is this a problem for Cassandra operations?**

*(Expected answer: 10M users × 500KB = ~5TB of blob data in one table. This causes: compaction runs that take hours as they must read and rewrite 5TB of blob data; bootstrap and repair that are dominated by streaming blob data rather than actual operational data; GC pressure on every read; and replication that copies each 500KB photo to all replicas on every update. Fix: migrate photos to S3 or GCS, store only the URL in Cassandra. The 5TB becomes a few hundred MB of URLs.)*

---

## See Also

**In this session:**
- [Huge Partitions](./01-huge-partitions.md)
- [Incorrect Compaction Strategy](./09-compaction-strategy.md)

**Reference:**
- [Compression](../../general/compression.md)
- [SSTable Components](../../general/sstable-components.md)
- [Streaming](../../general/streaming.md)
- [Node Density](../../general/node-density.md)
- [Compaction](../../general/compaction.md)
