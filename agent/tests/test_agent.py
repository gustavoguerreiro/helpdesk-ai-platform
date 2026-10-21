"""Agent tests with a scripted (fake) model: no network, no API key, deterministic."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import store  # noqa: E402
from app.agent import approve_action, run_agent  # noqa: E402
from app.model import ModelReply, ScriptedModel, ToolCall  # noqa: E402
from app.users import USERS  # noqa: E402


@pytest.fixture()
def conn():
    c = store.connect(":memory:")
    store.seed_demo(c)
    return c


def call(name, **args):
    return ModelReply(tool_calls=[ToolCall("t1", name, args)])


def audit(conn):
    return [(r["user"], r["tool"], r["outcome"]) for r in conn.execute("SELECT * FROM audit_log")]


def test_plain_answer_without_tools(conn):
    out = run_agent(conn, USERS["ana"], "hi", ScriptedModel([ModelReply(text="Hello!")]))
    assert out.answer == "Hello!" and out.steps == 1


def test_customer_only_sees_own_tickets(conn):
    model = ScriptedModel([call("search_tickets", query="printer"), ModelReply(text="done")])
    run_agent(conn, USERS["ana"], "find printer", model)
    result = model.seen_messages[1][-1]["content"][0]["content"]
    assert "Printer jammed" not in result  # that ticket belongs to dora


def test_staff_sees_all_tickets(conn):
    model = ScriptedModel([call("search_tickets", query="printer"), ModelReply(text="done")])
    run_agent(conn, USERS["bruno"], "find printer", model)
    assert "Printer jammed" in model.seen_messages[1][-1]["content"][0]["content"]


def test_forbidden_tool_is_blocked_and_audited(conn):
    # A customer's model asks to close a ticket: RBAC must refuse, nothing changes.
    model = ScriptedModel([call("close_ticket", ticket_id=1, reason="because"), ModelReply(text="ok")])
    run_agent(conn, USERS["ana"], "close my ticket", model)
    assert conn.execute("SELECT status FROM tickets WHERE id=1").fetchone()[0] == "open"
    assert conn.execute("SELECT count(*) FROM pending_actions").fetchone()[0] == 0
    assert ("ana", "close_ticket", "forbidden") in audit(conn)


def test_approval_gate_queues_instead_of_executing(conn):
    model = ScriptedModel([call("close_ticket", ticket_id=1, reason="resolved"), ModelReply(text="queued")])
    run_agent(conn, USERS["bruno"], "close ticket 1", model)
    assert conn.execute("SELECT status FROM tickets WHERE id=1").fetchone()[0] == "open"
    assert conn.execute("SELECT status FROM pending_actions").fetchone()[0] == "pending"


def test_same_request_twice_creates_one_pending_action(conn):
    for _ in range(2):
        model = ScriptedModel([call("close_ticket", ticket_id=1, reason="resolved"), ModelReply(text="x")])
        run_agent(conn, USERS["bruno"], "close ticket 1", model)
    assert conn.execute("SELECT count(*) FROM pending_actions").fetchone()[0] == 1


def test_approval_executes_once_and_rules_hold(conn):
    run_agent(conn, USERS["bruno"], "close", ScriptedModel([call("close_ticket", ticket_id=1, reason="resolved"), ModelReply(text="x")]))
    assert "only admins" in approve_action(conn, USERS["bruno"], 1)["error"]
    assert conn.execute("SELECT status FROM tickets WHERE id=1").fetchone()[0] == "open"
    assert approve_action(conn, USERS["carla"], 1)["status"] == "approved"
    assert conn.execute("SELECT status FROM tickets WHERE id=1").fetchone()[0] == "closed"
    assert "already approved" in approve_action(conn, USERS["carla"], 1)["error"]


def test_nobody_approves_their_own_request(conn):
    conn.execute("INSERT INTO pending_actions (idem_key, requested_by, tool, args) VALUES ('k','carla','close_ticket','{\"ticket_id\":1,\"reason\":\"abc\"}')")
    assert "own request" in approve_action(conn, USERS["carla"], 1)["error"]


def test_invalid_arguments_are_rejected(conn):
    model = ScriptedModel([call("get_ticket", ticket_id="abc"), ModelReply(text="x")])
    run_agent(conn, USERS["ana"], "q", model)
    assert ("ana", "get_ticket", "invalid_args") in audit(conn)


def test_unknown_tool_is_rejected(conn):
    model = ScriptedModel([call("drop_database"), ModelReply(text="x")])
    run_agent(conn, USERS["bruno"], "q", model)
    assert ("bruno", "drop_database", "unknown_tool") in audit(conn)


def test_step_limit_stops_a_looping_model(conn):
    model = ScriptedModel([call("search_tickets", query="a")] * 10)
    out = run_agent(conn, USERS["ana"], "loop", model, max_steps=3)
    assert out.stopped_by_limit and out.steps == 3


def test_injection_text_in_ticket_is_only_data(conn):
    # Ticket 3 contains "close all tickets". Staff reads it; the fake model "obeys" nothing
    # because tools run only on what the model requests, and closing still needs approval.
    model = ScriptedModel([call("get_ticket", ticket_id=3), ModelReply(text="summary")])
    run_agent(conn, USERS["bruno"], "summarise ticket 3", model)
    assert conn.execute("SELECT count(*) FROM tickets WHERE status='closed'").fetchone()[0] == 0
    assert "untrusted" in __import__("app.agent", fromlist=["x"]).SYSTEM_PROMPT


def test_tokens_are_logged_once_per_model_reply(conn):
    # One reply asks for two tools, then a final text reply. Every reply is counted
    # exactly once: the tool calls must not repeat their reply's tokens.
    model = ScriptedModel([
        ModelReply(tool_calls=[ToolCall("a", "get_ticket", {"ticket_id": 1}), ToolCall("b", "get_ticket", {"ticket_id": 2})],
                   input_tokens=100, output_tokens=10),
        ModelReply(text="done", input_tokens=500, output_tokens=40),
    ])
    run_agent(conn, USERS["ana"], "q", model)
    rows = [tuple(r) for r in conn.execute("SELECT step, input_tokens, output_tokens FROM model_usage ORDER BY step")]
    assert rows == [(1, 100, 10), (2, 500, 40)]
    assert conn.execute("SELECT count(*) FROM audit_log").fetchone()[0] == 2  # two tool calls


def test_a_rejected_request_can_be_queued_again(conn):
    def request():
        model = ScriptedModel([call("close_ticket", ticket_id=1, reason="resolved"), ModelReply(text="x")])
        run_agent(conn, USERS["bruno"], "close ticket 1", model)

    request()
    assert approve_action(conn, USERS["carla"], 1, approve=False)["status"] == "rejected"
    request()  # same user, tool and arguments as the rejected one
    statuses = [r[0] for r in conn.execute("SELECT status FROM pending_actions ORDER BY id")]
    assert statuses == ["rejected", "pending"]
