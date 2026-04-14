# Big Trie-Indexed (BTI) SSTable Format

**Recommendation: Use BTI for all Cassandra 5.0 deployments.**

BTI is the new SSTable format introduced in Cassandra 5.0 via [CEP-25](https://cwiki.apache.org/confluence/display/CASSANDRA/CEP-25%3A+Trie-indexed+SSTable+format). The name stands for **Big Trie-Indexed** — it shares the data format of the existing BIG SSTable format and only changes the primary indexes inside SSTables, replacing them with trie-based structures.

## Enabling BTI

Select BTI as the active SSTable format:

```yaml
# cassandra.yaml
sstable:
  selected_format: bti
```

BTI also requires running in a non-legacy storage-compatibility mode, which unlocks 5.0 features in general:

```yaml
# cassandra.yaml
storage_compatibility_mode: NONE
```

Cassandra can read both BTI and legacy BIG format SSTables, so migration is seamless. Existing BIG SSTables are converted to BTI as they are compacted.

**Note:** The key cache is not used with BTI — the trie index is efficient enough without it. Keep the key cache enabled until all SSTables have been rewritten to BTI format, then it can be disabled.

## Why BTI Matters

The legacy BIG format uses a B-tree style partition index with a sampled index summary held in memory. This works, but the index summary grows with the number of partitions, and lookups require O(log² n) comparisons (binary search over keys, where each comparison is itself O(log n) in key length).

BTI replaces this with a trie that maps byte-ordered partition key prefixes directly to data file positions. This gives:

- **Smaller index files** — tries share prefixes, avoiding redundant storage. Only the shortest unique prefix of each key is stored.
- **Faster lookups** — O(log n) transitions in the common case (hash-prefixed keys), where each transition is a constant-time operation. No key comparisons during traversal.
- **Lower memory overhead** — no index summary needed. Non-leaf trie pages serve the same purpose more efficiently.
- **Better out-of-cache performance** — page-aware layout ensures each disk page fetch yields multiple useful transitions.

## Prerequisites: Byte-Comparable Types and Tries

### Byte-Comparable Types

A key is byte-comparable (byte-ordered) when there exists a serialization to a byte sequence where lexicographic comparison of the unsigned bytes produces the same result as typed comparison of the key. Cassandra's byte-ordered representation is provided by [CASSANDRA-6936](https://issues.apache.org/jira/browse/CASSANDRA-6936).

This is what makes trie indexing possible — keys from any Cassandra type can be mapped into a uniform byte sequence that sorts correctly, allowing the trie to operate purely on bytes without understanding the underlying types.

### Tries

A trie is a tree where vertices are states (some final, holding a payload), and edges are labelled with characters (in our case, bytes). A word is valid if a path from the root exists where edge labels spell out the word and the final state holds its associated value.

Key properties:
- **Lookup is O(len(word))** — follow transitions for each byte of the key.
- **No redundant prefixes** — all words sharing a prefix store that prefix once.
- **Ordered** — a trie over lexicographically ordered keys is itself an ordered structure, supporting range queries and iteration.
- **Set algebra** — union, intersection, and slicing can be applied lazily and efficiently, benefiting from prefix sharing.

## How Trie Indexing Works

### The Basic Idea

When writing the index, each key is converted to its byte-ordered representation and inserted into an on-disk trie mapping byte sequences to positions in the data file. Lookup converts the query key to byte-ordered form and follows transitions in the trie.

### Unique Prefix Trimming

The index only needs to distinguish between keys that actually exist in the SSTable. Since the data file contains a copy of the full key at each partition's position, the index can store just the **shortest unique prefix** of each key — enough to differentiate it from all other keys in the file.

This typically reduces the trie to about 2n nodes (where n is the number of keys). For well-balanced key sets (like Murmur-partitioned keys that start with a hash), lookup complexity becomes **O(log n) transitions** — each transition is constant-time, so this is theoretically optimal.

For comparison, binary search in a sorted index is also O(log n) comparisons, but each comparison is itself O(log n) in key length, for a total of O(log² n).

### Page-Aware Layout

Raw trie performance is bottlenecked by disk page fetches. The BTI format uses a page-aware layout that packs wide sections of the trie into 4096-byte pages, ensuring that each disk page fetch yields several usable transitions.

The construction works bottom-up: when a branch grows larger than a page, its children are laid out together and the parent is treated as a leaf from there on. This approach is better than top-down (breadth-first) packing because it maximizes the amount of data in leaf pages, keeping the set of intermediate (non-leaf) pages as small as possible — which is the set that ideally stays cached.

**In practice:** if an SSTable is in active use, all non-leaf pages of the trie tend to remain in the page cache. Lookup then requires fetching only **one leaf index page** and **one data page** — the same number of seeks as the legacy index, but reading less data and doing less processing.

## Node Types and Storage Format

Trie nodes use typed encoding to minimize space. Each node starts with one byte: 4 bits of node type + 4 bits of payload information.

| Type | Description | When used |
|------|-------------|-----------|
| `PAYLOAD_ONLY` | Final node, no transitions | Leaf nodes — the majority of all nodes |
| `SINGLE` | One transition, stores character + target | Single-transition chains (common in key interiors) |
| `SPARSE` | Binary-searched list of transitions | Most common non-leaf type after `PAYLOAD_ONLY` |
| `DENSE` | Consecutive range of transitions | Nodes near the root where most byte values are present |

The format picks whichever type produces the smallest encoding for each node. Near the root, `DENSE` nodes dominate — lookups there are a direct array offset calculation (constant time). Near the leaves, `SPARSE` and `SINGLE` nodes avoid wasting space on empty transitions.

### Pointer Sizes

Pointers are stored as **distances** (the child is always before the parent in the file, so the distance is subtracted to find the child position). Most transitions are within the same page and use only 12 bits. Each node type has subtypes for different pointer widths: `DENSE_12`, `DENSE_16`, up to `DENSE_LONG` (64-bit), and similarly for `SPARSE` and `SINGLE`.

Node size examples (excluding payload):

| Type | Size for 1 child | Size for 9 dense children | Size for 10 sparse children |
|------|------------------:|---------------------------:|-----------------------------:|
| `SINGLE_NOPAYLOAD_4` | 2 bytes | — | — |
| `SPARSE_8` | 4 bytes | 20 bytes | 22 bytes |
| `DENSE_12` | 5 bytes | 18 bytes | — |
| `SPARSE_16` | 5 bytes | 29 bytes | 32 bytes |
| `DENSE_16` | 5 bytes | 23 bytes | — |
| `DENSE_32` | 7 bytes | 43 bytes | — |
| `DENSE_LONG` | 11 bytes | 83 bytes | — |

All nodes are aligned so they never cross a page boundary — a reader positioned at a node can always read all of its data without fetching another page.

## Partition Index

The partition index is stored in the `-Partitions.db` file. It maps byte-ordered partition key prefixes to either:

- A position in the **row index file** (for wide partitions that have their own row index), or
- A position in the **data file** (for small partitions where a row index isn't needed)

A single table can have both indexed and non-indexed partitions. The sign bit of the stored position long distinguishes the two cases.

### Lookup

1. Convert the decorated partition key to its byte-ordered representation.
2. Starting at the root, follow transitions for each byte of the key.
3. If a leaf is reached, it points to the data file or row index. The full partition key is stored at that position — compare it against the query key.
4. If the comparison matches, we found the partition. If not, the SSTable has no data for this key.
5. If at any point there's no transition for the next byte (and we're not at a leaf), the key doesn't exist in this SSTable.

### Reducing False Positives

When a leaf is reached but the full key comparison fails ("mismatch"), we've done an extra disk seek for nothing. Two mechanisms reduce mismatches:

1. **Bloom filters** — checked before the trie lookup. A bloom filter hit + a trie prefix match for the wrong key is extremely unlikely.
2. **Hash bits** — the payload at each leaf node stores some bits of the key's hash (not part of the token). These are compared before fetching the data page for the full key comparison.

Both are used by default. The combination makes mismatches vanishingly rare even at large scale.

### Building and Early Open

The index is built incrementally from sorted keys during SSTable construction. Each key is delayed until the next key is seen, so that the shortest differentiating prefix can be computed. Only that prefix is written to the trie.

For early-open support (allowing newly-compacted SSTables to gradually enter the page cache), the partially-written trie is made usable by dumping the not-yet-written intermediate nodes (the path from root to the last written node) to an in-memory buffer, attached to the end of the partially written file.

## Row Index

The row index maps clustering keys within a partition to data positions. Unlike the partition index (which maps exact keys), the row index primarily supports **iteration** from a given clustering key in forward or reverse direction.

### Block-Based Indexing

To avoid the row index becoming larger than the data it describes (rows can be very small), the index operates on **blocks** rather than individual rows. A block is at least 16KB of row data (controlled by `column_index_size` in `cassandra.yaml`).

Between blocks, the index stores a **separator** — a key that is greater than the last key of the previous block and less than or equal to the first key of the next block. Using the shortest such separator (similar to the unique prefix approach in the partition index) keeps the index compact while minimizing false positives.

### Lookup and Iteration

To find a clustering key:
1. Walk the trie to find the closest less-than-or-equal separator.
2. The associated payload gives the data position for the start of that block.
3. Walk forward within the block to find the exact row.

If the key falls between the last row of a block and the separator (false positive), the forward walk simply reaches the next block — correctness is preserved, just one extra block of scanning.

### Reverse Iteration

Forward iteration can simply walk the data file. Reverse iteration cannot. The row index provides a **reverse block iterator**: for each block, the iteration walks forward through it building a stack of row positions, then pops from the stack to iterate in reverse. When the stack is exhausted, the previous block is fetched.

### Granularity Tuning

The 16KB default block size (`column_index_size`) is conservative. Lower values produce larger indexes but faster lookups:

| Granularity | Index size | Lookup speed | Use case |
|-------------|------------|--------------|----------|
| 16KB (default) | Smallest | Good | General purpose |
| 4KB | Moderate | Better | Read-heavy partitions |
| 1KB | Larger | Much better | Frequent exact-match within partitions |
| 0KB (every row) | Largest | Fastest | Extreme read optimization; trie-indexed SSTables can outperform memtable reads |

### Active Deletions

If a range deletion is active at the start of a block, the row index stores the deletion time alongside the block's data position. This ensures correct merge behavior when reading from multiple SSTables.

## On-Disk File Layout

### Partition Index (`-Partitions.db`)

```
[trie nodes page, 4096 bytes]
...
[trie nodes page, 4096 bytes]
[trie nodes page including root node, ≤4096 bytes]
[smallest key, with short length]
[largest key, with short length]
[smallest key position, long]
[key count, long]
[root position, long]
```

The file is written bottom-up. The "header" (last 3 longs) contains the position of the first/last key serializations, the exact key count, and the root node position.

### Row Index (within `-Partitions.db`)

Each partition's row index:

```
[trie nodes page, 4096 bytes]
...
[trie nodes page including root node, ≤4096 bytes]
[partition key, with short length]
[data file position of partition, unsigned vint]
[root node position, vint delta from data position]
[row count, unsigned vint]
[partition deletion time, 12 bytes]
```

### Payload Encoding

Partition index leaf payloads:
- If payload bits (pb) < 8: a sign-extended integer of length pb giving the position (positive = row index, negative bitwise-complement = direct data position)
- If pb ≥ 8 (always the case in Cassandra 5.0): one byte of key hash bits, then a sign-extended integer of length pb-7 giving the position

Row index leaf payloads:
- pb & 7 bytes: offset within the partition to the start of the row's index block
- If pb ≥ 8: 12 bytes of deletion time active at the start of the block

## See Also

- [SSTable Components](sstable-components.md)
- [Compaction](compaction.md)
- [Cassandra 5.0 Notable Features](../cassandra-5.0/notable-features.md)
- [Node Density](node-density.md)
- [Streaming](streaming.md)
- [Memtables](memtables.md)
- [CEP-25: Trie-indexed SSTable format](https://cwiki.apache.org/confluence/display/CASSANDRA/CEP-25%3A+Trie-indexed+SSTable+format)
