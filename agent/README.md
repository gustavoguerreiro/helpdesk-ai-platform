# agent: helpdesk assistant with permissions and human approval

**Problem.** Let an LLM use tools on real data without letting it do anything the user
is not allowed to do, and without letting it make risky changes on its own.

## Flow

```
question -> model -> tool call? -> [known tool? valid args? role allowed? needs approval?] -> run -> result back to model -> ... -> answer
```

| Layer | Where | What it stops |
|---|---|---|
| Argument validation | `tools.py` (Pydantic) | malformed or out-of-range inputs |
| Role check (RBAC) | `agent.py: execute_tool_call` | a customer using a staff-only tool |
| Data scoping | `tools.py: _visible_tickets` | a customer reading someone else's ticket |
| Approval gate | `agent.py: queue_for_approval` / `approve_action` | risky writes running without a human |
| Step limit | `agent.py: run_agent` | an endless tool loop (cost and time) |
| Audit log | `store.py` table `audit_log` | no trace of who called which tool, with what outcome and latency |
| Usage log | `store.py` table `model_usage` | no record of tokens and latency per model reply (cost tracking) |

Ideas worth saying out loud:
- **The model is never the security boundary.** Permissions are checked in code on every
  call, even for tools that were not advertised to it.
- **Approval is a database row**, not a chat message. The request survives restarts, can
  be reviewed, and an idempotency key makes repeated requests collapse into one pending
  action.
- **Ticket text is untrusted data.** The system prompt says so and, more importantly, even
  a fooled model cannot close a ticket without an admin approving it.
- **Two kinds of permission.** The role decides which tools you may use; data scoping
  decides which rows a tool returns. Both are needed.

## Files

| File | What it is |
|---|---|
| `app/users.py` | Four demo identities and their roles |
| `app/tools.py` | The tool registry: argument model, allowed roles, approval flag, handler |
| `app/agent.py` | The loop, the safety layers, the approval functions |
| `app/store.py` | SQLite tables: `tickets`, `pending_actions`, `audit_log`, `model_usage` |
| `app/model.py` | The `Model` interface, `ScriptedModel` (tests) and `AnthropicModel` (real) |
| `app/main.py` | FastAPI: `/chat`, `/actions/pending`, `/actions/{id}/approve`, `/actions/{id}/reject` |
| `tests/test_agent.py` | 14 tests that act as the specification |

## Presenting it, file by file

About 8 minutes. For each file: open it, say the point, show the evidence. Everything in the
"Show" lines runs without an API key.

### 1. `app/tools.py` (2 minutes)
- **Open:** the `Tool` dataclass and the `TOOLS` registry at the bottom.
- **Point:** a tool is data, not just a function: a Pydantic argument model (validated
  before anything runs), `allowed_roles`, `requires_approval`, and a handler. `schema()`
  turns the argument model into the JSON schema sent to the model. `close_ticket` is staff
  only and needs approval. `_visible_tickets` is the data-level rule: customers only get
  their own rows. `get_ticket` answers "not found" both for a missing id and for someone
  else's ticket, so ids do not leak.
- **Show:** `pytest agent -v -k "own_tickets or staff_sees"`.

### 2. `app/agent.py`, `execute_tool_call` (2 minutes, the core)
- **Open:** the function and the numbered layer comments.
- **Point:** one tool call passes five checks in order: unknown tool, invalid arguments,
  role not allowed, needs approval (saved, not run), then execute. Each outcome is written
  to `audit_log`, allowed or not. The role comes from the authenticated user, never from the
  model.
- **Show:** `pytest agent -v -k "forbidden or invalid or unknown"`, and point
  at the `audit()` helper in `tests/test_agent.py`, which reads `audit_log` to show the trail.

### 3. `app/agent.py`, `run_agent` (1 minute)
- **Point:** the loop. Advertise only the tools the user may use (fewer wrong calls, less to
  leak; still re-checked on every call). Echo the assistant turn, answer every tool call
  with a result, ask again. Stop on a plain-text reply or at `max_steps`, so a looping model
  cannot spend forever. After every model reply, tokens and latency go to `model_usage`.
- **Show:** `pytest agent -v -k "step_limit or tokens"`.

### 4. `app/agent.py`, approval (1.5 minutes)
- **Point:** `queue_for_approval` stores the action with an idempotency key (a hash of who,
  tool and arguments), so a model that asks twice creates one pending action; the key only
  collides with a pending row, so a rejected request can be asked again. `approve_action`
  enforces: only admins, nobody approves their own request, and an already decided action
  cannot run twice. The arguments are validated again before running.
- **Show:** `pytest agent -v -k "approval or same_request or own_request or rejected"`.

### 5. `app/store.py` (45 seconds)
- **Point:** four tables. `pending_actions` has a partial unique index
  (`WHERE status = 'pending'`) that implements the idempotency rule. `audit_log` is per tool
  call; `model_usage` is per model reply, because tokens belong to the model call (one reply
  can request several tools, and the final answer requests none). SQLite stands in for
  PostgreSQL.

### 6. `app/model.py` (45 seconds)
- **Point:** the loop only knows a one-method interface. `ScriptedModel` returns pre-written
  replies, which makes tests fast, free and deterministic. `AnthropicModel` is a thin
  translation to the Messages API.
- **Say openly:** `AnthropicModel` has never been run (no API key was available).

### 7. `app/main.py` (30 seconds)
- **Point:** a thin HTTP layer. The `X-User` header is fake authentication; production needs
  a verified token. `/actions/pending` and approve/reject are admin-only.

## Run

```bash
pip install -r agent/requirements.txt
pytest agent -q                                  # 14 tests, no API key needed
export ANTHROPIC_API_KEY=...                     # only for the real model
cd agent && uvicorn app.main:app --reload
curl -H "X-User: bruno" -H "content-type: application/json" \
     -d '{"question":"Close ticket 1, it is resolved"}' localhost:8000/chat
curl -H "X-User: carla" localhost:8000/actions/pending
curl -X POST -H "X-User: carla" localhost:8000/actions/1/approve
```

Users: `ana`, `dora` (customers), `bruno` (agent), `carla` (admin).

## What is tested and what is only an example

Tested (14 tests with a scripted fake model): plain answer, customer sees only own tickets,
staff sees all, forbidden tool blocked and audited, approval queues instead of executing,
duplicate requests give one pending action, a rejected request can be queued again, approval
runs once and only for admins, nobody approves their own request, invalid arguments, unknown
tool, step limit, tokens counted once per model reply.

The injection test is weak by design: the scripted model never obeys the injected text, so
it shows that tools run only when requested and that closing needs approval, not that a real
model resists the attack.

Only an example, not tested here:
- `AnthropicModel` (the real API adapter) was never run: no API key in this environment.
- The `X-User` header is fake auth. Production needs a verified token (JWT / Entra ID).
- SQLite stands in for PostgreSQL.
- Only 3 tools and no SQL tool. A "ask the database" tool would need a read-only role (see
  `db-lab/init/01-roles.sql`), a statement allowlist and a row limit.

## Known limits

- **Approval runs the tool as the approver.** `approve_action` calls the handler with the
  admin's identity and does not re-check the requester's role or whether the ticket changed
  since the request. Fine for `close_ticket`; risky for tools whose result depends on the
  caller's data scope.
- **Decisions are not in `audit_log`.** Approve and reject are recorded in `pending_actions`
  (`decided_by`, `status`), not as audit rows.
- **One shared SQLite connection** (`check_same_thread=False`) used by every request. Fine
  for a demo, not for concurrent traffic; use a connection pool on PostgreSQL.
- **`search_tickets` filters in Python.** It loads every visible ticket and matches text in
  memory. A real tool would filter in SQL with a limit.
- **`/chat` has no timeout, retry or per-user budget.** A new `AnthropicModel` is created per
  request, and `max_tokens` is fixed at 1024.
- **No evals.** Behavior of a real model on tool choice and refusals is not measured.
- **No notification of the approver.** Pending actions are found by polling the endpoint.

## Trade-offs

- Advertising only permitted tools reduces wrong calls but is not enforcement; both are done.
- The model sees "pending approval" and tells the user; it cannot wait for the human, which
  keeps requests short but means the result of the action arrives in a later interaction.
- Approval gates add latency and a human bottleneck. Gate only actions that change state or
  cost money, and keep read tools free.
- Logging every model reply costs a write per step, in exchange for exact cost and latency
  figures per user.
- Next step for evals: a small set of golden questions scored on tool choice and answer
  correctness, run in CI against a cheap model.
