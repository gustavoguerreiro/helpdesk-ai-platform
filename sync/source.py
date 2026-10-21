"""Simulated source system.

In the real scenario the source would be Snowflake (or any warehouse/API). To keep
this project runnable without credentials, the source is an in-memory list that
behaves the same way from the sync's point of view: "give me rows changed after
this cursor, in a stable order, at most N at a time".

Swapping in a real source means implementing the same `fetch_changed` method
(for Snowflake: a SELECT ... WHERE (updated_at, id) > (%s, %s) ORDER BY updated_at, id LIMIT %s).
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class SourceRow:
    id: int
    name: str
    updated_at: datetime


class FakeSource:
    def __init__(self, rows: list[SourceRow] | None = None) -> None:
        self.rows: list[SourceRow] = list(rows or [])

    def upsert(self, row: SourceRow) -> None:
        """Simulate a change in the source: replace the row with the same id, or add it."""
        self.rows = [r for r in self.rows if r.id != row.id] + [row]

    def fetch_changed(self, after_updated: datetime, after_id: int, limit: int) -> list[SourceRow]:
        """Return rows strictly after the cursor (updated_at, id), oldest first.

        Tuple comparison is what makes the cursor exact: rows with the same
        timestamp are told apart by id, so nothing is skipped or repeated.
        """
        newer = [r for r in self.rows if (r.updated_at, r.id) > (after_updated, after_id)]
        newer.sort(key=lambda r: (r.updated_at, r.id))
        return newer[:limit]
