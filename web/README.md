# web: Next.js (App Router) + Prisma helpdesk

**Problem.** A small ticket app that shows the core Next.js + Prisma patterns:
server-rendered pages that query the database directly, a validated REST route,
a Server Action behind a form, and a connection setup that works with PgBouncer.

## Map

| File | What it shows |
|---|---|
| `prisma/schema.prisma` | Models, enums, indexes, `url` + `directUrl` for PgBouncer |
| `lib/prisma.ts` | PrismaClient singleton (avoids leaking pools on hot reload) |
| `lib/validation.ts` | One Zod schema shared by the API and the form |
| `app/page.tsx`, `app/tickets/[id]/page.tsx` | Server Components querying with `select`/`include` |
| `app/actions.ts` | Server Actions: validate, write, `revalidatePath`, idempotent close |
| `app/tickets/new/form.tsx` | The only Client Component (needed for form error state) |
| `app/api/tickets/route.ts` | `GET` with cursor pagination, `POST` with validation |
| `prisma/seed.ts` | Re-runnable seed |

## Run

```bash
cp ../.env.example .env && (cd .. && docker compose up -d)
npm ci
npx prisma migrate dev --name init   # creates prisma/migrations and applies it (uses the DIRECT url)
npm run db:seed
npm run dev                          # http://localhost:3000
npm test                             # validation tests (no database needed)
```

## PgBouncer and Prisma, in short

- The app connects through PgBouncer in **transaction** mode (`DATABASE_URL`, port 6432). Prisma then needs `?pgbouncer=true`, because transaction pooling cannot keep prepared statements alive on one server connection.
- Migrations use `directUrl` (port 5432) and skip the pooler, because they rely on session behavior.
- Do not open many PrismaClients: each has its own pool. Keep the singleton and set a small `connection_limit` per instance.

## What is tested and what is only an example

Tested here: the Zod validation (7 vitest tests).

**Verified (2026-10-21, Node 22 in a container, PostgreSQL 16 + PgBouncer from `docker-compose.yml`):** `prisma validate`, `prisma generate`, `prisma migrate dev --name init` (the result is committed in `prisma/migrations`), `npm run db:seed`, `npm run typecheck`, `npm test` (7 tests), `npm run build`, and `next start` against PgBouncer in transaction mode (`GET /`, `GET` and `POST /api/tickets`, including a 400 on invalid input and a 201 on a valid ticket).

**Still not verified:** the Server Action form in a real browser, and any auth flow (there is none).

Also only an example: `lib/session.ts` picks a demo user. Real authentication (Auth.js, or Entra ID / Easy Auth on Azure) is not implemented.

## Trade-offs

- Server Components query the database directly: less code and no extra API hop, but the data access is tied to the page. Shared logic should move into a `lib/` data layer as the app grows.
- Server Actions are convenient but are public endpoints; they validate input like any API.
- Cursor pagination cannot jump to "page 7", but stays fast and stable on large tables.
