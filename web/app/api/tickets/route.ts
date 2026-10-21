// REST-style route handler: the same capability as the pages, for other clients.
//   GET  /api/tickets?status=OPEN&cursor=42&limit=20
//   POST /api/tickets   { "title": "...", "body": "..." }
import { NextResponse } from "next/server";

import { prisma } from "@/lib/prisma";
import { getDemoUser } from "@/lib/session";
import { createTicketSchema, listQuerySchema } from "@/lib/validation";

export async function GET(request: Request) {
  const params = Object.fromEntries(new URL(request.url).searchParams);
  const parsed = listQuerySchema.safeParse(params);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const { status, cursor, limit } = parsed.data;

  // Fetch one extra row to know whether another page exists, without a COUNT(*).
  const rows = await prisma.ticket.findMany({
    where: { ...(status && { status }), ...(cursor && { id: { lt: cursor } }) },
    orderBy: { id: "desc" },
    take: limit + 1,
    select: { id: true, title: true, status: true, createdAt: true },
  });
  const hasMore = rows.length > limit;
  const items = hasMore ? rows.slice(0, limit) : rows;
  return NextResponse.json({ items, nextCursor: hasMore ? items[items.length - 1].id : null });
}

export async function POST(request: Request) {
  const json = await request.json().catch(() => null);
  const parsed = createTicketSchema.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const user = await getDemoUser();
  const ticket = await prisma.ticket.create({ data: { ...parsed.data, ownerId: user.id } });
  return NextResponse.json(ticket, { status: 201 });
}
