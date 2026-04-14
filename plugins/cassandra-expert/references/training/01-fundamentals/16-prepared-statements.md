# Topic: Prepared Statements

## Objective
Use prepared statements correctly in every language, understanding where they're automatic and where they must be done explicitly.

## Why This Matters

Unprepared statements parsed on every execution add unnecessary overhead to requests. String-concatenated queries also open the door to CQL injection. Prepared statements are non-negotiable for any query executed more than once.

---

## Concept

When Cassandra receives a CQL query, it must parse and plan it before executing. **Preparing** a statement does this work once and caches the result. Subsequent executions send only the binary statement ID and bound parameters — far less work for the cluster.

```
Unprepared:  [parse CQL] → [plan query] → [execute] → [return result]
             (every time)

Prepared:    [parse CQL] → [plan query] → [cache]   ← happens once at startup
Execution:   [binary ID + params] → [execute] → [return result]
             (every time, much cheaper)
```

### Benefits

| Benefit | Why It Matters |
|---------|---------------|
| **Performance** | Parse and plan happen once, not per request |
| **Reduced cluster CPU** | Less parsing work on Cassandra nodes |
| **Security** | Parameter binding prevents CQL injection |
| **Network efficiency** | Binary protocol with params is smaller than full CQL text |

### Per-Language Behavior

This is critical — it varies by driver. See `../../general/drivers.md` for the full driver reference including links and import paths.

| Language | Auto-Prepare? | What You Must Do |
|----------|--------------|-----------------|
| **Go (cassandra-gocql-driver)** | Yes | Nothing — prepares on first execution automatically |
| **Java** | **No** | Call `session.prepare()` explicitly |
| **Python** | **No** | Call `session.prepare()` explicitly |
| **Node.js** | **No** | Call `session.prepare()` explicitly |
| **C#** | **No** | Call `Prepare()` explicitly |

**Go developers**: The Apache `cassandra-gocql-driver` handles this for you. But you should still use `?` placeholders (not string concatenation) for security.

**Everyone else**: Prepare statements at application startup. Cache the `PreparedStatement` object. Never call prepare inside a request handler or a loop.

### Anti-Patterns

```python
# WRONG: string concatenation — CQL injection risk + no preparation
user_id = request.get('user_id')
session.execute(f"SELECT * FROM users WHERE user_id = {user_id}")

# WRONG: preparing inside a loop — re-prepares on every iteration
for user_id in user_ids:
    stmt = session.prepare("SELECT * FROM users WHERE user_id = ?")
    session.execute(stmt, [user_id])
```

---

## Examples

### Python — explicit preparation required
```python
from cassandra.cluster import Cluster
from cassandra.query import BatchStatement, BatchType

cluster = Cluster(['localhost'])
session = cluster.connect('my_keyspace')

# Prepare at startup — outside of any request handling
get_user = session.prepare("SELECT * FROM users WHERE user_id = ?")
insert_user = session.prepare(
    "INSERT INTO users (user_id, name, email) VALUES (?, ?, ?)"
)
update_email = session.prepare(
    "UPDATE users SET email = ? WHERE user_id = ?"
)

# Use throughout the application lifetime
def get_user_profile(user_id):
    return session.execute(get_user, [user_id]).one()

def create_user(user_id, name, email):
    session.execute(insert_user, [user_id, name, email])
```

### Java — explicit preparation required
```java
// Prepare once at application startup (e.g., in constructor or @PostConstruct)
public class UserRepository {
    private final CqlSession session;
    private final PreparedStatement getUser;
    private final PreparedStatement insertUser;
    private final PreparedStatement updateEmail;

    public UserRepository(CqlSession session) {
        this.session = session;
        // Prepare all statements at construction time
        this.getUser = session.prepare("SELECT * FROM users WHERE user_id = ?");
        this.insertUser = session.prepare(
            "INSERT INTO users (user_id, name, email) VALUES (?, ?, ?)"
        );
        this.updateEmail = session.prepare(
            "UPDATE users SET email = ? WHERE user_id = ?"
        );
    }

    public User getUser(UUID userId) {
        Row row = session.execute(getUser.bind(userId)).one();
        return row != null ? mapToUser(row) : null;
    }

    public void createUser(UUID userId, String name, String email) {
        session.execute(insertUser.bind(userId, name, email));
    }
}
```

### Go — automatic preparation, but still use placeholders
```go
import (
    "context"
    gocql "github.com/apache/cassandra-gocql-driver/v2"
)

// gocql automatically prepares on first execution — you don't call Prepare()
// Always use ? placeholders (never string concatenation) for security

func getUser(ctx context.Context, session *gocql.Session, userID gocql.UUID) (*User, error) {
    var user User
    err := session.Query(
        "SELECT user_id, name, email FROM users WHERE user_id = ?",
        userID,
    ).ScanContext(ctx, &user.ID, &user.Name, &user.Email)

    if err == gocql.ErrNotFound {
        return nil, nil
    }
    return &user, err
}

func createUser(ctx context.Context, session *gocql.Session, userID gocql.UUID, name, email string) error {
    return session.Query(
        "INSERT INTO users (user_id, name, email) VALUES (?, ?, ?)",
        userID, name, email,
    ).ExecContext(ctx)
}
```

### Node.js — explicit preparation required
```javascript
// Prepare at startup
const getUser = await client.prepare('SELECT * FROM users WHERE user_id = ?');
const insertUser = await client.prepare(
  'INSERT INTO users (user_id, name, email) VALUES (?, ?, ?)'
);

// Execute with bound parameters
async function getUserProfile(userId) {
  const result = await client.execute(getUser, [userId]);
  return result.first();
}
```

---

## Pulse Check

> You're code-reviewing a Java service that processes 5,000 user requests per second. You find this in the request handler:
>
> ```java
> public User getUser(UUID userId) {
>     return session.execute(
>         "SELECT * FROM users WHERE user_id = " + userId
>     ).one();
> }
> ```
>
> **What are the two problems with this code? How do you fix it?**

*(Expected answer: Problem 1 — string concatenation instead of parameter binding, which is a CQL injection risk. Problem 2 — the query is not prepared, so Cassandra parses and plans it 5,000 times per second. Fix: prepare the statement once at startup (e.g., in the constructor), cache the `PreparedStatement`, and use `.bind(userId)` in the handler.)*

---

## See Also

**In this session:**
- [DML Basics — INSERT, UPDATE, DELETE, SELECT](./09-dml-basics.md)
- [Pattern: Single Key](./17-pattern-single-key.md)

**Reference:**
- [Prepared Statements](../../general/prepared-statements.md)
- [Drivers](../../general/drivers.md)
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
