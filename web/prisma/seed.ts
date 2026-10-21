// Seed data for local development. Safe to re-run (upserts by unique email).
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  const ana = await prisma.user.upsert({
    where: { email: "ana@example.com" },
    update: {},
    create: { email: "ana@example.com", name: "Ana", role: "CUSTOMER" },
  });
  await prisma.user.upsert({
    where: { email: "carla@example.com" },
    update: {},
    create: { email: "carla@example.com", name: "Carla", role: "ADMIN" },
  });
  if ((await prisma.ticket.count()) === 0) {
    await prisma.ticket.createMany({
      data: [
        { title: "VPN does not connect", body: "Error 809 since this morning.", ownerId: ana.id },
        { title: "Need access to shared drive", body: "Please add me to Finance.", ownerId: ana.id },
      ],
    });
  }
}

main().finally(() => prisma.$disconnect());
