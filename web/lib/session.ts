// DEMO ONLY. A real app would read the signed-in user from a verified session or
// token (for example Auth.js, or Entra ID / Easy Auth on Azure). Here we just pick
// the first customer so the pages have an "owner" to attach tickets to.
import { prisma } from "@/lib/prisma";

export async function getDemoUser() {
  return prisma.user.findFirstOrThrow({ where: { role: "CUSTOMER" }, orderBy: { id: "asc" } });
}
