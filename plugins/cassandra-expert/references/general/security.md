# Security

## Authentication

**Never run a production cluster with `AllowAllAuthenticator`.** It allows unrestricted access to all data with no audit trail.

```yaml
# cassandra.yaml
authenticator: PasswordAuthenticator
authorizer: CassandraAuthorizer
```

**First thing after enabling auth:** change the default `cassandra` superuser password.

```cql
ALTER ROLE cassandra WITH PASSWORD = 'strong_password_here';
```

Then create dedicated roles per application — never share the superuser account:

```cql
CREATE ROLE app_user WITH PASSWORD = 'strong_password' AND LOGIN = true;
GRANT SELECT ON KEYSPACE app_keyspace TO app_user;
```

## Enabling Authentication on a Running Cluster

This requires a rolling restart. The cluster stays available throughout.

1. Update `cassandra.yaml` on each node: set `authenticator: PasswordAuthenticator` and `authorizer: CassandraAuthorizer`
2. Restart nodes one at a time — wait for each to reach Up/Normal before proceeding
3. After all nodes are restarted, connect and change the default password
4. Create application users and grant appropriate permissions
5. Update application connection strings

```bash
# Per node
nodetool drain
systemctl stop cassandra
systemctl start cassandra
nodetool status  # Wait for UN before moving to next node
```

## Authorization

Use `CassandraAuthorizer` alongside `PasswordAuthenticator`. Grant minimum necessary permissions.

```cql
-- Read-only application user
GRANT SELECT ON KEYSPACE app_keyspace TO readonly_user;

-- Write access to specific table
GRANT MODIFY ON TABLE app_keyspace.events TO writer_user;

-- Review permissions
LIST ALL PERMISSIONS OF app_user;

-- Review all roles
LIST ROLES;
```

## Audit Logging (Cassandra 4.0+)

Cassandra 4.0 introduced built-in audit logging via Full Query Logging (FQL):

```yaml
# cassandra.yaml
audit_logging_options:
  enabled: true
  logger:
    - class_name: BinAuditLogger
  audit_logs_dir: /var/log/cassandra/audit
  included_categories: AUTH,DCL,DDL
```

Monitor for:
- Failed authentication attempts (potential brute force)
- Unexpected permission changes
- Role creation or deletion

## Best Practices

- Change the default `cassandra` password immediately on every new cluster
- Create one role per application with minimum necessary permissions
- Use different credentials per environment (dev/staging/prod)
- Disable or drop unused roles
- Enable audit logging in production (4.0+)
- Rotate passwords on a regular schedule

## Network Encryption

Enable TLS for both client-to-node and inter-node communication. Without encryption, queries, data, and credentials are transmitted in plaintext.

### Client-to-Node

```yaml
# cassandra.yaml
client_encryption_options:
  enabled: true
  optional: false
  keystore: /path/to/keystore.jks
  keystore_password: keystore_password
```

### Inter-Node

```yaml
# cassandra.yaml
server_encryption_options:
  internode_encryption: all
  keystore: /path/to/keystore.jks
  keystore_password: keystore_password
  truststore: /path/to/truststore.jks
  truststore_password: truststore_password
  require_client_auth: true
```

**`internode_encryption` options:**
- `all` — encrypt everything (recommended)
- `dc` — encrypt only cross-DC traffic (trusted intra-DC network)
- `none` — never use in production

### Enabling Encryption on a Running Cluster

Two-phase rolling restart:

1. Set `optional: true` on all nodes, rolling restart — both encrypted and unencrypted connections are accepted
2. Update all application clients to use TLS
3. Set `optional: false` on all nodes, rolling restart — unencrypted connections are now rejected

### Certificate Management

- Use certificates from a proper CA for production
- Monitor certificate expiration and alert before expiry
- Plan and document a rotation procedure
- Protect keystore/truststore files — readable only by the Cassandra user

TLS adds 5–15% CPU overhead. Use hardware with AES-NI support.

## See Also

- `cluster-configuration.md` — ensure auth and encryption settings are consistent across all nodes
