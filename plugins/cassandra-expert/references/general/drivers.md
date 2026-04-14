# Cassandra Client Drivers

## Go

**Apache cassandra-gocql-driver**
https://github.com/apache/cassandra-gocql-driver

The official Apache-maintained Go driver for Cassandra. Formerly known as `gocql`, now maintained under the Apache Software Foundation.

```go
import gocql "github.com/apache/cassandra-gocql-driver/v2"
```

**Key behaviors:**
- Always use `?` placeholders (not string concatenation) for security
- Use `context.Context` with `ExecContext`, `ScanContext`, `IterContext` for cancellation and tracing

---

## Java

**Apache cassandra-java-driver**
https://github.com/apache/cassandra-java-driver

```xml
<dependency>
    <groupId>org.apache.cassandra</groupId>
    <artifactId>java-driver-core</artifactId>
</dependency>
```

**Key behaviors:**
- Prepare statements once at startup, cache the `PreparedStatement` object
- Use `session.execute(prepared.bind(...))` for execution

---

## Python

**Apache cassandra-python-driver**
https://github.com/apache/cassandra-python-driver

```bash
pip install cassandra-driver
```

**Key behaviors:**
- Prepare statements once at module/app startup
- Use `session.execute(prepared, [params])` for execution

---

## Node.js

**Apache cassandra-nodejs-driver**
https://github.com/apache/cassandra-nodejs-driver

```bash
npm install cassandra-driver
```

**Key behaviors:**
- Use `client.execute(prepared, params)` for execution

---

## C# / .NET

**DataStax C# Driver**
https://github.com/datastax/csharp-driver

```bash
dotnet add package CassandraCSharpDriver
```

> **Note:** This is the only non-Apache driver in this list. At the time of writing, there is no Apache-maintained C# driver for Cassandra — the DataStax driver remains the standard choice for .NET applications. It is still actively maintained and compatible with open-source Cassandra.

**Key behaviors:**
- Cache and reuse `PreparedStatement` objects

---

## C / C++

**Apache cassandra-cpp-driver**
https://github.com/apache/cassandra-cpp-driver

**Key behaviors:**
- Manage `CassPrepared` object lifetime manually

---

## Bulk Analytics

**Apache cassandra-analytics**
https://github.com/apache/cassandra-analytics

Spark-based bulk read/write framework for Cassandra. Use for large-scale data processing, ETL pipelines, and analytics workloads that would be impractical with a regular driver.

---

## Quick Reference

| Driver | Link |
|--------|------|
| Go (cassandra-gocql-driver) | https://github.com/apache/cassandra-gocql-driver |
| Java | https://github.com/apache/cassandra-java-driver |
| Python | https://github.com/apache/cassandra-python-driver |
| Node.js | https://github.com/apache/cassandra-nodejs-driver |
| C# | https://github.com/datastax/csharp-driver |
| C/C++ | https://github.com/apache/cassandra-cpp-driver |
| Bulk Analytics (Spark) | https://github.com/apache/cassandra-analytics |

## See Also

- [Prepared Statements](prepared-statements.md)
- [CQL Anti-Patterns](cql-anti-patterns.md)
- [Thread Pools](thread-pools.md)
