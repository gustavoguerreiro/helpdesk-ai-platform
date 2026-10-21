"""Tests for the incremental sync. They need a real PostgreSQL (set TEST_DATABASE_URL);
they are skipped when none is reachable. Each test uses its own schema."""
import os
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import psycopg
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sync as sync_mod  # noqa: E402
from source import FakeSource, SourceRow  # noqa: E402

DSN = os.environ.get("TEST_DATABASE_URL", "postgresql://postgres@/lab?host=/tmp&port=5544")
T0 = datetime(2026, 1, 1, tzinfo=timezone.utc)


@pytest.fixture()
def conn():
    try:
        c = psycopg.connect(DSN)
    except Exception:
        pytest.skip("PostgreSQL not available for sync tests")
    schema = "t_" + uuid.uuid4().hex[:8]
    c.execute(f"CREATE SCHEMA {schema}")
    c.execute(f"SET search_path TO {schema}")
    c.execute((Path(__file__).resolve().parents[1] / "schema.sql").read_text())
    c.commit()
    yield c
    c.rollback()
    c.execute(f"DROP SCHEMA {schema} CASCADE")
    c.commit()
    c.close()


def rows(n, start=1, ts=None):
    return [SourceRow(i, f"c{i}", ts or T0 + timedelta(seconds=i)) for i in range(start, start + n)]


def count(conn):
    return conn.execute("SELECT count(*) FROM customers").fetchone()[0]


def test_first_run_copies_everything_in_batches(conn):
    result = sync_mod.run_sync(conn, FakeSource(rows(25)), batch_size=10)
    assert (result.batches, result.rows_read) == (3, 25)
    assert count(conn) == 25


def test_second_run_is_a_noop(conn):
    src = FakeSource(rows(5))
    sync_mod.run_sync(conn, src)
    again = sync_mod.run_sync(conn, src)
    assert again.rows_read == 0 and count(conn) == 5


def test_only_changed_rows_are_picked_up(conn):
    src = FakeSource(rows(5))
    sync_mod.run_sync(conn, src)
    src.upsert(SourceRow(3, "renamed", T0 + timedelta(days=1)))
    result = sync_mod.run_sync(conn, src)
    assert result.rows_read == 1
    assert conn.execute("SELECT name FROM customers WHERE id = 3").fetchone()[0] == "renamed"
    assert count(conn) == 5  # updated in place, no duplicate


def test_many_rows_with_the_same_timestamp_are_not_lost(conn):
    # 30 rows share one timestamp and the batch is smaller than that.
    # A cursor on updated_at alone would loop or skip; (updated_at, id) does not.
    sync_mod.run_sync(conn, FakeSource(rows(30, ts=T0)), batch_size=7)
    assert count(conn) == 30


def test_replaying_an_old_row_never_overwrites_a_newer_one(conn):
    src = FakeSource([SourceRow(1, "new", T0 + timedelta(days=2))])
    sync_mod.run_sync(conn, src)
    # Replay an older version directly through the batch writer.
    sync_mod.apply_batch(conn, [SourceRow(1, "old", T0)])
    conn.commit()
    assert conn.execute("SELECT name FROM customers WHERE id = 1").fetchone()[0] == "new"


def test_failed_batch_leaves_cursor_unchanged(conn):
    bad = [SourceRow(1, None, T0 + timedelta(seconds=1))]  # NULL name violates NOT NULL
    with pytest.raises(psycopg.errors.NotNullViolation):
        sync_mod.run_sync(conn, FakeSource(bad))
    cursor = sync_mod.read_cursor(conn)
    assert cursor[1] == 0  # cursor did not move, so the batch will be retried


def test_freshness_check(conn):
    sync_mod.run_sync(conn, FakeSource(rows(1, ts=datetime.now(timezone.utc) - timedelta(minutes=2))))
    ok, _ = sync_mod.check_freshness(conn, timedelta(minutes=5))
    stale, _ = sync_mod.check_freshness(conn, timedelta(seconds=30))
    assert ok is True and stale is False
