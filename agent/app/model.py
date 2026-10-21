"""Model adapters. The agent loop only knows this tiny interface, which is what
makes it testable: tests use ScriptedModel, production uses AnthropicModel."""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Protocol


@dataclass
class ToolCall:
    id: str
    name: str
    args: dict


@dataclass
class ModelReply:
    text: str = ""
    tool_calls: list[ToolCall] = field(default_factory=list)
    input_tokens: int = 0
    output_tokens: int = 0


class Model(Protocol):
    def respond(self, system: str, messages: list[dict], tools: list[dict]) -> ModelReply: ...


class ScriptedModel:
    """A fake model that returns pre-written replies in order. Used by the tests
    so they are fast, free and deterministic. It records what it was sent."""

    def __init__(self, replies: list[ModelReply]) -> None:
        self.replies = list(replies)
        self.seen_messages: list[list[dict]] = []

    def respond(self, system, messages, tools) -> ModelReply:
        self.seen_messages.append([dict(m) for m in messages])
        return self.replies.pop(0) if self.replies else ModelReply(text="(script ended)")


class AnthropicModel:
    """Real model through the Anthropic Messages API.

    NOT exercised by the automated tests (they would need an API key and money).
    It is a thin translation layer between our types and the SDK's.
    """

    def __init__(self, model: str | None = None) -> None:
        import anthropic  # imported here so tests do not need a key

        self.client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY
        self.model = model or os.environ.get("AGENT_MODEL", "claude-sonnet-5-5")

    def respond(self, system, messages, tools) -> ModelReply:
        resp = self.client.messages.create(
            model=self.model, max_tokens=1024, system=system, messages=messages, tools=tools
        )
        reply = ModelReply(input_tokens=resp.usage.input_tokens, output_tokens=resp.usage.output_tokens)
        for block in resp.content:
            if block.type == "text":
                reply.text += block.text
            elif block.type == "tool_use":
                reply.tool_calls.append(ToolCall(block.id, block.name, dict(block.input)))
        return reply
