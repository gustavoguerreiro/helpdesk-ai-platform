// One PrismaClient per process.
//
// Why a singleton: in development Next.js reloads modules on every change, and each
// new PrismaClient opens its own connection pool. Without this guard you would leak
// pools until the database refuses connections. We keep the instance on `globalThis`
// so hot reloads reuse it.
import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === "development" ? ["query", "warn", "error"] : ["error"],
  });

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = prisma;
