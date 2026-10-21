"use client";
// Client Component: needed only because the form shows validation errors using
// React state (useActionState). Everything else in this app stays on the server.
import { useActionState } from "react";

import { createTicket } from "@/app/actions";

export function NewTicketForm() {
  const [state, formAction, pending] = useActionState(createTicket, undefined);
  return (
    <form action={formAction} style={{ display: "grid", gap: "0.75rem" }}>
      <input name="title" placeholder="Title" required />
      <textarea name="body" placeholder="What is wrong?" rows={5} required />
      {state?.error && <p role="alert" style={{ color: "crimson" }}>{state.error}</p>}
      <button type="submit" disabled={pending}>{pending ? "Saving..." : "Create ticket"}</button>
    </form>
  );
}
