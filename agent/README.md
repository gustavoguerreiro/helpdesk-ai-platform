# agent: helpdesk assistant with permissions and human approval

**Problem.** Let an LLM use tools on real data without letting it do anything the
user is not allowed to do, and without letting it make risky changes on its own.

## Flow

```
question -> model -> tool call? -> [unknown? valid args? role allowed? needs approval?] -> run -> result back to model -> ... -> answer
```

| Layer | Where | What it stops |
|---|---|---|
| Argument validation | `tools.py` (Pydantic) | malformed or out-of-range inputs |
| Role check (RBAC) | `agent.py: execute_tool_call` | a customer using a staff-only tool |
| Data scoping | `tools.py: _visible_tickets` | a customer reading someone else's ticket |
| Approval gate | `agent.py: queue_for_approval` / `approve_action` | risky writes running without a human |
| Step limit | `agent.py: run_agent` | an endless tool loop (cost and time) |
| Audit log | `store.py` table `audit_log` | no trace of who did what, tokens, latency |

Key ideas worth saying out loud:
- **The model is never the security boundary.** Permissions are checked in code on every call, even for tools we did not advertise.
- **Approval is a database row**, not a chat message. The request survives restarts, can be reviewed, and a unique idempotency key means repeated requests collapse into one.
- **Ticket text is untrusted data.** The system prompt says so, and, more importantly, even a fooled model cannot close a ticket without an admin approving it.

## Run

```bash
pip install -r agent/requirements.txt
pytest agent -q                                  # 13 tests, no API key needed
export ANTHROPIC_API_KEY=...                     # only for the real model
cd agent && uvicorn app.main:app --reload
curl -H "X-User: bruno" -H "content-type: application/json" \
     -d '{"question":"Close ticket 1, it is resolved"}' localhost:8000/chat
curl -H "X-User: carla" localhost:8000/actions/pending
curl -X POST -H "X-User: carla" localhost:8000/actions/1/approve
```

Users: `ana`, `dora` (customers), `bruno` (agent), `carla` (admin).

## What is tested and what is only an example

Tested (13 tests with a scripted fake model): plain answer, customer sees only own
tickets, staff sees all, forbidden tool blocked and audited, approval queues instead
of executing, duplicate requests give one pending action, approval runs once and
only for admins, nobody approves their own request, invalid arguments, unknown tool,
step limit, tokens logged.

Only an example, not tested here:
- `AnthropicModel` (the real API adapter) was never run: no API key in this environment.
- The `X-User` header is fake auth. Production needs a verified token (JWT / Entra ID).
- SQLite stands in for PostgreSQL.
- Only 3 tools; no SQL tool. A "ask the database" tool would need a read-only role
  (see `db-lab/init/01-roles.sql`), a statement allowlist and a row limit.

## Trade-offs

- Advertising only permitted tools reduces wrong calls but is not enforcement; both are done.
- The model sees "pending approval" and tells the user; it cannot wait for the human, which keeps requests short.
- No evals on real model behavior yet. Next step: a small set of golden questions
  scored on tool choice and answer correctness, run in CI against a cheap model.
