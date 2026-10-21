// Ticket detail page with a "Close" button that calls a Server Action.
import { notFound } from "next/navigation";

import { closeTicket } from "@/app/actions";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

// In Next.js 15, `params` is a Promise and must be awaited.
export default async function TicketPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ticketId = Number(id);
  if (!Number.isInteger(ticketId) || ticketId <= 0) notFound();

  const ticket = await prisma.ticket.findUnique({
    where: { id: ticketId },
    include: { owner: { select: { name: true } } },
  });
  if (!ticket) notFound();

  return (
    <main>
      <h1>{ticket.title}</h1>
      <p>
        {ticket.status} · opened by {ticket.owner.name}
      </p>
      {/* React escapes this text, so HTML typed by a user cannot run as script. */}
      <p>{ticket.body}</p>
      {ticket.status !== "CLOSED" && (
        // `.bind` pre-fills the action argument on the server side.
        <form action={closeTicket.bind(null, ticket.id)}>
          <button type="submit">Close ticket</button>
        </form>
      )}
    </main>
  );
}
