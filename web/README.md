# web: Next.js (App Router) + Prisma helpdesk

**Problem.** Most of a web app is the same few questions: where does the code run
(server or browser), how does it reach the database without exhausting connections,
how is input validated, and how does the page know its data changed. This small
ticket app answers each one with the standard Next.js 15 + Prisma 6 pattern, on top
of the PostgreSQL + PgBouncer stack from `docker-compose.yml`.

## What the app does

- `/` lists the 50 newest tickets.
- `/tickets/new` creates a ticket through a form.
- `/tickets/[id]` shows a ticket and lets you close it.
- `/api/tickets` is a JSON API: `GET` (filter by status, cursor pagination) and `POST`.

## Architecture in one picture

```
Browser
  │  HTML, or a form post / fetch
  ▼
Next.js server (App Router)
  ├─ Server Components   app/page.tsx, app/tickets/[id]/page.tsx   read data, render HTML
  ├─ Client Component    app/tickets/new/form.tsx                   form state only
  ├─ Server Actions      app/actions.ts                             writes from forms
  └─ Route Handler       app/api/tickets/route.ts                   JSON API
        │  all four use the same two helpers
        ├─ lib/validation.ts   Zod schemas (one set of rules)
        └─ lib/prisma.ts       PrismaClient singleton
              │  DATABASE_URL (pgbouncer=true)
              ▼
         PgBouncer :6432  (transaction pooling)
              ▼
         PostgreSQL :5432      ◄── prisma migrate uses DATABASE_DIRECT_URL, skipping the pooler
```

## Map

| File | What it is | Concept to know |
|---|---|---|
| `prisma/schema.prisma` | Models (`User`, `Ticket`), enums, indexes, `url` + `directUrl` | Single source of truth for the data model; `migrate dev` turns changes into SQL |
| `prisma/migrations/` | The generated SQL, committed | Applied in order by `migrate deploy` in CI and production |
| `prisma/seed.ts` | Two users and two tickets | Upserts by unique email, so it is safe to re-run |
| `lib/prisma.ts` | PrismaClient singleton on `globalThis` | Dev hot reload would otherwise open a new connection pool on every change |
| `lib/validation.ts` | `createTicketSchema`, `listQuerySchema` (Zod) | One schema shared by the API and the form, so rules cannot drift |
| `lib/session.ts` | `getDemoUser()` returns the first customer | Placeholder for real authentication |
| `app/page.tsx` | Ticket list | Server Component with `select` (does not fetch the long `body`) |
| `app/tickets/[id]/page.tsx` | Ticket detail and Close button | In Next.js 15 `params` is a Promise; `notFound()` for bad ids |
| `app/tickets/new/form.tsx` | New ticket form | The only Client Component: it needs state to show errors (`useActionState`) |
| `app/actions.ts` | `createTicket`, `closeTicket` | Server Actions: validate, write, `revalidatePath`, redirect |
| `app/api/tickets/route.ts` | JSON API | Cursor pagination, fetches `limit + 1` rows to know if there is a next page |
| `tests/validation.test.ts` | 7 vitest tests of the Zod schemas | Pure functions, no database needed |

## Request flows

**List page (`GET /`).** The server runs `prisma.ticket.findMany` and sends HTML.
`export const dynamic = "force-dynamic"` makes it render on every request, so a ticket
created a second ago shows up. No JavaScript from this page runs in the browser.

**Create a ticket (form).** The browser submits the form to `createTicket`. It
validates with `createTicketSchema`; on failure it returns `{ error }` and the form
shows it. On success it inserts the row, calls `revalidatePath("/")` (marks the list
as stale) and redirects to the new ticket.

**Close a ticket.** The button submits `closeTicket.bind(null, id)`. The update uses
`updateMany` with `status: { not: "CLOSED" }`, so a double click changes 0 rows the
second time and nothing breaks.

**API (`/api/tickets`).** `GET` validates the query string, then reads
`WHERE id < cursor ORDER BY id DESC LIMIT limit + 1`. Returning `nextCursor` instead
of a page number keeps deep pages fast and stable while rows are being added.
`POST` validates the JSON body and returns 201, or 400 with the field errors.

## Concepts, short version

- **Server Component vs Client Component.** Server Components run only on the server,
  can query the database, and send HTML. Client Components (`"use client"`) also ship
  JavaScript to the browser. Use the second only when you need state or events.
- **Server Action.** A function marked `"use server"` that a form can call directly.
  Under the hood it is a public HTTP endpoint, so it must validate input and check
  permissions like any API route.
- **`revalidatePath`.** Tells Next.js a cached page is stale after a write.
- **PrismaClient singleton.** Each client owns a connection pool. One per process.
- **`url` vs `directUrl`.** `url` is the runtime connection through PgBouncer with
  `?pgbouncer=true` (no prepared statements, which transaction pooling cannot keep).
  `directUrl` is used only by the Prisma CLI for migrations, which need session
  features such as locks and DDL transactions.
- **Migrations.** `prisma migrate dev` creates SQL files in `prisma/migrations`;
  commit them. `prisma migrate deploy` applies them in CI and production.
- **SQL injection.** Prisma sends parameterized queries. React escapes rendered text.

## Run

```bash
cp ../.env.example .env && (cd .. && docker compose up -d)
npm ci
npx prisma migrate dev --name init   # applies prisma/migrations (uses the DIRECT url)
npm run db:seed
npm run dev                          # http://localhost:3000
npm test                             # validation tests (no database needed)
```

If port 5432 is taken, start Postgres with `POSTGRES_PORT=5433 docker compose up -d`
and use 5433 in `DATABASE_DIRECT_URL`.

## What is tested and what is only an example

**Verified (2026-10-21, Node 22 in a container, PostgreSQL 16 + PgBouncer from
`docker-compose.yml`):** `prisma validate`, `prisma generate`, `prisma migrate dev --name init`
(committed in `prisma/migrations`), `npm run db:seed`, `npm run typecheck`, `npm test`
(7 tests), `npm run build`, and `next start` against PgBouncer in transaction mode:
`GET /` returned 200, `GET /api/tickets` listed the seeded tickets, and `POST /api/tickets`
returned 400 for invalid input and 201 for a valid ticket. CI runs the same steps
(except the database ones) on every push.

**Not verified:** the Server Action forms in a real browser, and the behavior under
load or with many connections.

## Known gaps (this is a demo, not production)

- **No authentication.** `lib/session.ts` picks the first customer. A real app would
  use Auth.js, or Entra ID through Easy Auth on Azure.
- **No authorization.** `closeTicket` and `GET /api/tickets` do not check who is
  calling, and the list shows every user's tickets. Any caller can close any ticket
  by id. Fix: read the user from the session, check role and ownership in every
  action and route, and scope queries by owner or team.
- **Row Level Security is not wired in.** `db-lab/07` shows the pattern (a
  transaction with `SET LOCAL`), but this app does not use it, and `.env.example`
  connects as the `helpdesk` superuser, which bypasses RLS. A real setup connects as
  a role like `app_user`.
- **Index and query do not match.** The index is `(status, createdAt DESC)`, but the
  API orders by `id`. The list page matches the index; the cursor query may not use
  it well on a large table. Not checked with `EXPLAIN` here because the table is tiny.
- **Dependencies.** `npm audit` reports vulnerabilities (not reviewed).
- **UI.** Inline styles only; no Tailwind or component library.

## Trade-offs

- Server Components query the database directly: less code and no extra API hop, but
  the data access is tied to the page. Shared logic should move to a data layer in
  `lib/` as the app grows.
- Server Actions are convenient but are public endpoints; they need the same
  validation and authorization as an API.
- Cursor pagination cannot jump to "page 7", but stays fast and stable on large tables.
- `force-dynamic` is simple and always fresh, but every request hits the database.
  Caching plus `revalidatePath` saves database load at the cost of more moving parts.
- One Zod schema shared by API and form keeps rules consistent, but the API and the
  form still return errors in different shapes.
