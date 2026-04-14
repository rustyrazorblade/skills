# OS Settings for Cassandra

Critical operating system settings that must be configured correctly on every Cassandra node. Wrong defaults cause severe performance degradation or data corruption.

## Readahead

**Set readahead to 4KB (8 sectors) on all data drives.**

The OS default (often 128KB–1MB) causes massive read amplification for Cassandra's random-access workload. Cassandra reads small, targeted blocks — large readahead fetches data that is never used, wastes IOPS, and pollutes the page cache.

```bash
# Check current readahead (in 512-byte sectors; 8 = 4KB)
blockdev --getra /dev/sda

# Set immediately
blockdev --setra 8 /dev/sda
```

**Exception:** Compaction internally uses larger sequential reads — this is handled within Cassandra and does not require a higher OS readahead setting.

See also: `compaction.md` — compaction throughput tuning.

## Disk Access Mode

**Always use `mmap_index_only` in `cassandra.yaml`.** This is the only correct setting.

```yaml
# cassandra.yaml
disk_access_mode: mmap_index_only
```

| Setting | Result |
|---------|--------|
| `mmap_index_only` | Index files mapped, data files use standard I/O — correct |
| `auto` | Maps data files on 64-bit JVMs — causes page fault storms |
| `mmap` | Aggressively maps everything — catastrophic when data > RAM |
| `standard` | No mapping at all — slower index access, not recommended |

**Why data file mapping is dangerous:** When data size exceeds node RAM, the OS continuously swaps pages in and out. This causes unpredictable read latency, GC pressure, and can lead to OOM conditions and cluster instability.

Applies to all Cassandra versions (3.x, 4.x, 5.0+).

## Swap

**Disable swap entirely on all Cassandra nodes.**

Swapping JVM heap to disk is catastrophic — it causes multi-second GC pauses, query timeouts, and cascading cluster instability.

```bash
# Disable immediately
sudo swapoff -a

# Remove from /etc/fstab to survive reboots
sudo sed -i '/swap/d' /etc/fstab

# Set swappiness to 0 (no swap partition) or 1 (if swap must exist)
echo "vm.swappiness=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -w vm.swappiness=1

# Verify
free -h        # Swap line should show 0
swapon --show  # Should be empty
```

**Never use `vm.swappiness > 1`.** Linux will swap even with free RAM available.

## Clock Synchronization

**CRITICAL: All Cassandra nodes AND application clients must have synchronized clocks.**

Cassandra uses timestamps for last-write-wins conflict resolution. Clients supply their own timestamps. Clock drift causes silent data corruption: writes from a node with a fast clock will win over later deletes from a node with the correct time, causing deleted data to reappear.

**Recommended: chrony** (more accurate and faster convergence than NTP)

```bash
# Install and enable chrony
sudo apt-get install chrony          # Debian/Ubuntu
sudo yum install chrony              # RHEL/CentOS

sudo systemctl enable chronyd
sudo systemctl start chronyd

# Verify synchronization
chronyc tracking
chronyc sources
```

**AWS:** Use the Amazon Time Sync Service endpoint:
```
server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4
```

**Alert thresholds:**
- Warning: drift > 500ms
- Critical: drift > 1 second or time sync service down

**Do not forget application clients.** They write timestamps too. A single application server with a drifted clock can cause widespread data integrity issues.

## Applying Settings Consistently

Use configuration management (Ansible, Chef, Puppet) to enforce these settings cluster-wide. Inconsistent settings across nodes make performance unpredictable and troubleshooting extremely difficult.

Verify after any OS upgrade — kernel updates can reset udev rules and sysctl values.

## See Also

- [Compaction](compaction.md) — compaction throughput tuning
- [JVM](jvm.md)
- [Disk Configuration](disk-configuration.md)
- [Hardware](hardware.md)
