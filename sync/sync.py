"""Incremental, idempotent feed from a source into PostgreSQL.

Design in one paragraph:
  1. Read the cursor (last_updated, last_id) from sync_state.
  2. Ask the source for the next batch of rows after that cursor.
  3. In ONE transaction: load the batch into a staging table, upsert into the
     destination, and move the cursor forward.
  4. Repeat until the source has nothing newer.

Why this is safe to retry:
  * The upsert is keyed by id, so replaying a batch does not create duplicates.
  * The cursor moves in the SAME transaction as the data. Either both happen or
    neither does, so a crash can never leave the cursor ahead of the data
    (which would silently lose rows) or leave data without moving the cursor
    (which only means the batch is reprocessed, and that is harmless).
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import psycopg

from source import FakeSource

FEED = "customers"


@dataclass
class SyncResult:
    batches: int
    rows_read: int


def read_cursor(conn: psycopg.Connection) -> tuple[datetime, int]:
    """Return the saved cursor, creating the state row on the first run."""
    conn.execute("INSERT INTO sync_state (feed) VALUES (%s) ON CONFLICT DO NOTHING", (FEED,))
    row = conn.execute(
        "SELECT last_updated, last_id FROM sync_state WHERE feed = %s", (FEED,)
    ).fetchone()
    return row[0], row[1]


def apply_batch(conn: psycopg.Connection, rows: list) -> None:
    """Write one batch and advance the cursor, atomically (the caller commits)."""
    # A TEMP table is private to this transaction and disappears at commit.
    # Loading into staging first lets us upsert the whole batch with ONE statement
    # instead of one round trip per row.
    conn.execute(
        "CREATE TEMP TABLE IF NOT EXISTS stg_customers "
        "(id BIGINT, name TEXT, updated_at TIMESTAMPTZ) ON COMMIT DROP"
    )
    conn.execute("TRUNCATE stg_customers")
    with conn.cursor() as cur:
        cur.executemany(
            "INSERT INTO stg_customers (id, name, updated_at) VALUES (%s, %s, %s)",
            [(r.id, r.name, r.updated_at) for r in rows],
        )

    # Upsert. The WHERE clause is a guard: never overwrite a row with an OLDER
    # version (this can happen if a batch is replayed after a newer one landed).
    conn.execute(
        """
        INSERT INTO customers (id, name, updated_at, synced_at)
        SELECT id, name, updated_at, now() FROM stg_customers
        ON CONFLICT (id) DO UPDATE
          SET name = EXCLUDED.name,
              updated_at = EXCLUDED.updated_at,
              synced_at = now()
          WHERE customers.updated_at < EXCLUDED.updated_at
        """
    )

    # Advance the cursor to the last row of the batch (rows are ordered).
    last = rows[-1]
    conn.execute(
        "UPDATE sync_state SET last_updated = %s, last_id = %s, last_run_at = now() WHERE feed = %s",
        (last.updated_at, last.id, FEED),
    )


def run_sync(conn: psycopg.Connection, source: FakeSource, batch_size: int = 1000) -> SyncResult:
    """Pull everything newer than the cursor, one transaction per batch."""
    batches = rows_read = 0
    while True:
        last_updated, last_id = read_cursor(conn)
        conn.commit()  # end the read transaction so each batch starts clean

        rows = source.fetch_changed(last_updated, last_id, batch_size)
        if not rows:
            break

        try:
            apply_batch(conn, rows)
            conn.commit()          # data and cursor become visible together
        except Exception:
            conn.rollback()        # nothing changed; the next run retries this batch
            raise

        batches += 1
        rows_read += len(rows)
    return SyncResult(batches=batches, rows_read=rows_read)


def check_freshness(conn: psycopg.Connection, max_lag: timedelta) -> tuple[bool, timedelta]:
    """Is the destination close enough to the source?

    "Lag" here is how old the newest synced row is. In a real system you would
    compare with the source's own newest timestamp and alert (for example from
    Grafana or an Azure Monitor alert rule) when lag exceeds the agreed limit.
    """
    row = conn.execute(
        "SELECT last_updated FROM sync_state WHERE feed = %s", (FEED,)
    ).fetchone()
    if row is None:
        return False, timedelta.max
    lag = datetime.now(timezone.utc) - row[0]
    return lag <= max_lag, lag


if __name__ == "__main__":
    import os

    # Demo run: generate some fake source rows, sync them, print the result.
    dsn = os.environ.get("DATABASE_DIRECT_URL", "postgresql://helpdesk:helpdesk_dev_password@localhost:5432/helpdesk")
    from source import SourceRow

    now = datetime.now(timezone.utc)
    src = FakeSource([SourceRow(i, f"Customer {i}", now - timedelta(minutes=10 - i % 10)) for i in range(1, 2501)])
    with psycopg.connect(dsn) as conn:
        conn.execute(open("schema.sql").read())
        conn.commit()
        result = run_sync(conn, src, batch_size=1000)
        ok, lag = check_freshness(conn, timedelta(minutes=15))
        print(f"batches={result.batches} rows={result.rows_read} fresh={ok} lag={lag}")
        sys.exit(0 if ok else 1)
