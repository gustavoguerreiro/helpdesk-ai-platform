// Ticket list. This is a Server Component: it runs on the server, queries the
// database directly with Prisma and sends only HTML to the browser.
import Link from "next/link";

import { prisma } from "@/lib/prisma";

// Always render on request, so a ticket created a second ago is visible.
// (Alternative: cache and rely on revalidatePath, as actions.ts does.)
export const dynamic = "force-dynamic";

export default async function Home() {
  const tickets = await prisma.ticket.findMany({
    orderBy: { createdAt: "desc" },
    take: 50,
    // `select` fetches only what the page renders (not the long body text).
    select: { id: true, title: true, status: true, owner: { select: { name: true } } },
  });

  return (
    <main>
      <h1>Tickets</h1>
      <ul>
        {tickets.map((t) => (
          <li key={t.id}>
            <Link href={`/tickets/${t.id}`}>{t.title}</Link> · {t.status} · {t.owner.name}
          </li>
        ))}
      </ul>
    </main>
  );
}
