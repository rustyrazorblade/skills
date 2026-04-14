# Topic: User-Defined Types (UDTs)

## Objective
Understand what a UDT is, when to use one, and the important distinction between frozen and non-frozen UDTs.

## Why This Matters
Cassandra lets you define your own composite types — a kind of lightweight struct — and use them as column values. UDTs can simplify schemas that would otherwise need many flat columns or awkward maps. But UDTs come with limitations (especially around updates), and using them in the wrong place creates maintenance problems. Knowing when a UDT is the right tool saves rewrites later.

---

## Concept

A **user-defined type (UDT)** is a named, typed struct of fields that can be used as a column type. Think of it as a row-within-a-row: you define the shape once, then store instances of that shape in columns.

```sql
CREATE TYPE address (
    street text,
    city text,
    state text,
    zip text
);
```

Once the type is defined, you can use it in a table:

```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    name text,
    home_address frozen<address>,
    work_address frozen<address>
);
```

UDTs are **bound to a keyspace** — a type defined in one keyspace cannot be used in another.

### Frozen vs Non-Frozen

This is the most important distinction to understand about UDTs.

- **`frozen<udt>`** — the UDT value is treated as an opaque blob. You can only set or replace the whole value; you cannot update individual fields.
- **Non-frozen UDT** — individual fields can be updated independently, like columns on a row.

In practice, **non-frozen UDTs have historically been limited** (they cannot be used as clustering columns, inside collections, or as part of a primary key). The rule of thumb: **use `frozen<udt>` unless you specifically need to update individual fields and know the restrictions.**

### Updating a Frozen UDT

Updates replace the entire value:

```sql
UPDATE users
SET home_address = { street: '100 Main St', city: 'Seattle', state: 'WA', zip: '98101' }
WHERE user_id = ?;
```

You can't do `UPDATE users SET home_address.city = 'Tacoma'` on a frozen UDT — you must rewrite the whole thing.

### When to Use a UDT

UDTs are a good fit when:
- You have a fixed set of related fields that are always read and written together (addresses, money amounts with currency, geo coordinates)
- You want the schema to document the structure explicitly
- The data doesn't need field-level updates

UDTs are a **poor** fit when:
- Fields need to be updated individually (use flat columns instead)
- The set of fields is dynamic or variable (use a map instead)
- You want to query by a field inside the UDT (Cassandra generally can't index into frozen UDT fields the way you'd expect)

### UDT vs Flat Columns vs Maps

| Need | Use |
|------|-----|
| Fixed, known set of fields always read together | UDT (frozen) |
| Fields that need independent updates | Flat columns |
| Dynamic, unknown set of keys | Map |

---

## Examples

### Defining and using a UDT
```sql
-- Define the type
CREATE TYPE money (
    amount decimal,
    currency text
);

-- Use it in a table
CREATE TABLE products (
    product_id uuid PRIMARY KEY,
    name text,
    price frozen<money>
);

-- Insert
INSERT INTO products (product_id, name, price)
VALUES (uuid(), 'Widget', { amount: 9.99, currency: 'USD' });
```

### A UDT containing a collection
```sql
CREATE TYPE contact (
    email text,
    phones set<text>,
    preferred_channel text
);

CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    name text,
    contact_info frozen<contact>
);
```

### Altering a UDT to add a field
```sql
-- Add a new field; existing values will have it as NULL
ALTER TYPE address ADD country text;
```

---

## Pulse Check

> You're designing a `users` table and need to store a user's home address. You're deciding between these two options:
>
> - Option A: flat columns `home_street`, `home_city`, `home_state`, `home_zip`
> - Option B: a UDT `address` used as `home_address frozen<address>`
>
> The application always reads and writes the full address together. Occasionally a user's city or zip changes.
>
> **Which would you choose, and what's the tradeoff?**

*(Expected answer: Either works, but frozen UDT (Option B) documents the structure more clearly and scales if a user could have multiple addresses in one row (home, work, billing). The tradeoff: updating just the city means rewriting the whole UDT value. If that's acceptable because you always update the full address anyway, UDT is fine. If individual fields need cheap independent updates, prefer flat columns.)*

> A colleague proposes defining a UDT `profile` with 20 fields and using it as a non-frozen column so individual fields can be updated. They want to be able to do `UPDATE users SET profile.email = ? WHERE user_id = ?`.
>
> **What concerns would you raise?**

*(Expected answer: Non-frozen UDTs are limited — they can't be used as clustering keys, inside collections, or in many contexts that frozen UDTs can. Historically, support for non-frozen UDTs has been restrictive. Unless there's a strong reason to use non-frozen, prefer flat columns for 20 independently-updatable fields. The UDT doesn't add much here — you still need 20 cells worth of writes, and flat columns give you more flexibility (easier to query, index, and alter over time).)*

---

## See Also

**In this session:**
- [Basic Types](./03-types.md)
- [Advanced Types — Collections, Static Columns, and Counters](./07-advanced-types.md)

**Reference:**
- [CQL Anti-Patterns](../../general/cql-anti-patterns.md)
- [Cassandra 5.0 Notable Features](../../cassandra-5.0/notable-features.md)
