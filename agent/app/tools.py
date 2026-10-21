"""Tool registry: what the model is allowed to ask for.

Each tool declares:
  * an input model (Pydantic)  -> arguments are validated before anything runs
  * allowed roles              -> RBAC is enforced HERE, in code, on every call.
                                  The model is never trusted to police itself.
  * requires_approval          -> risky writes are queued for a human instead of run.
"""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from typing import Callable

from pydantic import BaseModel, Field

from .users import User


class SearchArgs(BaseModel):
    query: str = Field(min_length=1, max_length=200)


class TicketArgs(BaseModel):
    ticket_id: int = Field(gt=0)


class CloseArgs(BaseModel):
    ticket_id: int = Field(gt=0)
    reason: str = Field(min_length=3, max_length=300)


@dataclass(frozen=True)
class Tool:
    name: str
    description: str
    args_model: type[BaseModel]
    allowed_roles: frozenset[str]
    requires_approval: bool
    handler: Callable[[sqlite3.Connection, User, BaseModel], dict]

    def schema(self) -> dict:
        """The JSON schema sent to the model so it knows how to call the tool."""
        return {
            "name": self.name,
            "description": self.description,
            "input_schema": self.args_model.model_json_schema(),
        }


def _visible_tickets(conn: sqlite3.Connection, user: User):
    """Data-level permission: customers only see their own tickets; staff see all.
    Role checks decide WHICH TOOLS you can use; this decides WHICH ROWS they return."""
    if user.role == "customer":
        return conn.execute("SELECT * FROM tickets WHERE owner = ?", (user.name,))
    return conn.execute("SELECT * FROM tickets")


def search_tickets(conn, user, args: SearchArgs) -> dict:
    q = args.query.lower()
    rows = [dict(r) for r in _visible_tickets(conn, user) if q in (r["title"] + r["body"]).lower()]
    return {"tickets": rows}


def get_ticket(conn, user, args: TicketArgs) -> dict:
    for r in _visible_tickets(conn, user):
        if r["id"] == args.ticket_id:
            return {"ticket": dict(r)}
    # Same message whether it does not exist or belongs to someone else:
    # do not leak which ids exist.
    return {"error": "ticket not found"}


def close_ticket(conn, user, args: CloseArgs) -> dict:
    cur = conn.execute("UPDATE tickets SET status = 'closed' WHERE id = ?", (args.ticket_id,))
    conn.commit()
    return {"closed": cur.rowcount == 1, "ticket_id": args.ticket_id, "reason": args.reason}


ALL_ROLES = frozenset({"customer", "agent", "admin"})
STAFF = frozenset({"agent", "admin"})

TOOLS: dict[str, Tool] = {
    t.name: t
    for t in [
        Tool("search_tickets", "Search tickets by text in title or body.", SearchArgs, ALL_ROLES, False, search_tickets),
        Tool("get_ticket", "Get one ticket by id.", TicketArgs, ALL_ROLES, False, get_ticket),
        # Writes that change state: staff only AND a human must approve.
        Tool("close_ticket", "Close a ticket with a reason.", CloseArgs, STAFF, True, close_ticket),
    ]
}
