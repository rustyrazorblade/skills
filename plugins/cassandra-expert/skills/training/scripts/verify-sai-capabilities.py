#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "cassandra-driver>=3.29",
# ]
# ///
"""Verify SAI column-kind and query-operator support on Cassandra 5.0+.

Runs CREATE INDEX ... USING 'sai' and SELECT ... attempts against a running
cluster and reports each as PASS/FAIL vs. expected. Use this to confirm
upstream documented behaviour before relying on it in training material —
backs claims in references/training/04-sai/ (in particular the
"What Columns Can Be Indexed" section in 03-creating-managing-indexes.md
and the "Text Matching" section in 04-querying-with-sai.md).

Usage:
    uv run verify-sai-capabilities.py [--host 127.0.0.1] [--port 9042]

Requires a reachable Cassandra 5.0+ cluster with an existing superuser account
or anonymous access. Creates and drops a dedicated keyspace `sai_verify`.
"""

import argparse
import sys

from cassandra.cluster import Cluster
from cassandra import InvalidRequest
from cassandra.protocol import SyntaxException

KEYSPACE = "sai_verify"

CASES = [
    {
        "name": "single-column partition key",
        "table": """
            CREATE TABLE t_single_pk (
                user_id uuid PRIMARY KEY,
                name    text
            )
        """,
        "index": "CREATE INDEX ON t_single_pk (user_id) USING 'sai'",
        "expect_accept": False,
    },
    {
        "name": "clustering column",
        "table": """
            CREATE TABLE t_clustering (
                user_id  uuid,
                event_id timeuuid,
                status   text,
                PRIMARY KEY (user_id, event_id)
            )
        """,
        "index": "CREATE INDEX ON t_clustering (event_id) USING 'sai'",
        "expect_accept": True,
    },
    {
        "name": "column of composite partition key",
        "table": """
            CREATE TABLE t_composite_pk (
                tenant_id uuid,
                region    text,
                event_id  timeuuid,
                body      text,
                PRIMARY KEY ((tenant_id, region), event_id)
            )
        """,
        "index": "CREATE INDEX ON t_composite_pk (region) USING 'sai'",
        "expect_accept": True,
    },
    {
        "name": "regular non-PK column",
        "table": """
            CREATE TABLE t_regular (
                user_id uuid PRIMARY KEY,
                email   text
            )
        """,
        "index": "CREATE INDEX ON t_regular (email) USING 'sai'",
        "expect_accept": True,
    },
    {
        "name": "counter column",
        "table": """
            CREATE TABLE t_counter (
                page_id text PRIMARY KEY,
                views   counter
            )
        """,
        "index": "CREATE INDEX ON t_counter (views) USING 'sai'",
        "expect_accept": False,
    },
]


OPERATOR_CASES = [
    {
        "name": "equality on indexed text column",
        "query": "SELECT * FROM t_text WHERE name = 'foo'",
        "expect_accept": True,
    },
    {
        "name": "range on indexed numeric column",
        "query": "SELECT * FROM t_text WHERE price > 10",
        "expect_accept": True,
    },
    {
        "name": "LIKE prefix match (rejected in Cassandra 5.0)",
        "query": "SELECT * FROM t_text WHERE name LIKE 'foo%'",
        "expect_accept": False,
    },
    # OR in WHERE is rejected with a syntax error by Apache Cassandra 5.0,
    # in all four common forms. These cases lock that behavior in so the
    # training material can be kept honest if it ever changes upstream.
    {
        "name": "top-level same-column OR (rejected in Cassandra 5.0)",
        "query": "SELECT * FROM t_text WHERE name = 'foo' OR name = 'bar'",
        "expect_accept": False,
    },
    {
        "name": "top-level cross-column OR (rejected in Cassandra 5.0)",
        "query": "SELECT * FROM t_text WHERE name = 'foo' OR price > 10",
        "expect_accept": False,
    },
    {
        "name": "parenthesized same-column OR scoped by PK (rejected)",
        "query": (
            "SELECT * FROM t_text "
            "WHERE id = 00000000-0000-0000-0000-000000000000 "
            "AND (name = 'foo' OR name = 'bar')"
        ),
        "expect_accept": False,
    },
    {
        "name": "parenthesized cross-column OR scoped by PK (rejected)",
        "query": (
            "SELECT * FROM t_text "
            "WHERE id = 00000000-0000-0000-0000-000000000000 "
            "AND (name = 'foo' OR price > 10)"
        ),
        "expect_accept": False,
    },
]


def run_column_cases(session) -> int:
    fail = 0
    for case in CASES:
        session.execute(case["table"])
        try:
            session.execute(case["index"])
            accepted = True
            err = None
        except InvalidRequest as e:
            accepted = False
            err = str(e).splitlines()[0]

        expected = "accept" if case["expect_accept"] else "reject"
        actual = "accept" if accepted else "reject"
        ok = accepted == case["expect_accept"]
        status = "PASS" if ok else "FAIL"
        if not ok:
            fail += 1

        print(f"[{status}] {case['name']:<50} expected={expected} actual={actual}")
        if not accepted and err:
            print(f"         server said: {err}")
    return fail


def run_operator_cases(session) -> int:
    session.execute(
        "CREATE TABLE t_text (id uuid PRIMARY KEY, name text, price int)"
    )
    session.execute("CREATE INDEX ON t_text (name) USING 'sai'")
    session.execute("CREATE INDEX ON t_text (price) USING 'sai'")

    fail = 0
    for case in OPERATOR_CASES:
        try:
            session.execute(case["query"])
            accepted = True
            err = None
        except (InvalidRequest, SyntaxException) as e:
            accepted = False
            err = str(e).splitlines()[0]

        expected = "accept" if case["expect_accept"] else "reject"
        actual = "accept" if accepted else "reject"
        ok = accepted == case["expect_accept"]
        status = "PASS" if ok else "FAIL"
        if not ok:
            fail += 1

        print(f"[{status}] {case['name']:<50} expected={expected} actual={actual}")
        if not accepted and err:
            print(f"         server said: {err}")
    return fail


def run(host: str, port: int) -> int:
    cluster = Cluster([host], port=port)
    session = cluster.connect()

    session.execute(f"DROP KEYSPACE IF EXISTS {KEYSPACE}")
    session.execute(
        f"CREATE KEYSPACE {KEYSPACE} "
        "WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1}"
    )
    session.set_keyspace(KEYSPACE)

    print("== Column-kind support ==")
    fail = run_column_cases(session)

    print()
    print("== Query operator support ==")
    fail += run_operator_cases(session)

    session.execute(f"DROP KEYSPACE {KEYSPACE}")
    cluster.shutdown()

    total = len(CASES) + len(OPERATOR_CASES)
    print()
    print(f"{total - fail}/{total} passed")
    return 0 if fail == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9042)
    args = parser.parse_args()
    return run(args.host, args.port)


if __name__ == "__main__":
    sys.exit(main())
