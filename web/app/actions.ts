"use server";
// Server Actions run on the server but can be called straight from a <form>.
// They are public HTTP endpoints under the hood, so they MUST validate input and
// check permissions just like an API route.
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { prisma } from "@/lib/prisma";
import { getDemoUser } from "@/lib/session";
import { createTicketSchema } from "@/lib/validation";

export type FormState = { error?: string } | undefined;

export async function createTicket(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = createTicketSchema.safeParse({
    title: formData.get("title"),
    body: formData.get("body"),
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const user = await getDemoUser();
  const ticket = await prisma.ticket.create({ data: { ...parsed.data, ownerId: user.id } });

  // The list page is cached by Next.js. Tell it this path is stale so the
  // next visit shows the new ticket.
  revalidatePath("/");
  redirect(`/tickets/${ticket.id}`);
}

export async function closeTicket(ticketId: number) {
  // Only the intended transition: OPEN/IN_PROGRESS -> CLOSED. updateMany with a
  // status filter makes a double click harmless (the second call updates 0 rows).
  await prisma.ticket.updateMany({
    where: { id: ticketId, status: { not: "CLOSED" } },
    data: { status: "CLOSED" },
  });
  revalidatePath("/");
  revalidatePath(`/tickets/${ticketId}`);
}
