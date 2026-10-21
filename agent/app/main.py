"""HTTP layer (FastAPI). Thin on purpose: all logic lives in agent.py.

DEMO AUTH WARNING: the X-User header stands in for a verified identity.
A real deployment must derive the user from a validated token."""
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

from . import store
from .agent import approve_action, run_agent
from .model import AnthropicModel
from .users import USERS, User

app = FastAPI(title="helpdesk agent")
conn = store.connect("agent.db")
store.seed_demo(conn)


def current_user(x_user: str = Header()) -> User:
    user = USERS.get(x_user)
    if user is None:
        raise HTTPException(401, "unknown user")
    return user


class Chat(BaseModel):
    question: str


@app.post("/chat")
def chat(body: Chat, user: User = Depends(current_user)):
    result = run_agent(conn, user, body.question, AnthropicModel())
    return {"answer": result.answer, "steps": result.steps}


@app.get("/actions/pending")
def pending(user: User = Depends(current_user)):
    if user.role != "admin":
        raise HTTPException(403, "admins only")
    return [dict(r) for r in conn.execute("SELECT * FROM pending_actions WHERE status='pending'")]


@app.post("/actions/{action_id}/approve")
def approve(action_id: int, user: User = Depends(current_user)):
    return approve_action(conn, user, action_id, True)


@app.post("/actions/{action_id}/reject")
def reject(action_id: int, user: User = Depends(current_user)):
    return approve_action(conn, user, action_id, False)
