import { describe, expect, it } from "vitest";

import { createTicketSchema, listQuerySchema } from "../lib/validation";

describe("createTicketSchema", () => {
  it("accepts a valid ticket and trims whitespace", () => {
    const r = createTicketSchema.parse({ title: "  VPN down  ", body: "details" });
    expect(r.title).toBe("VPN down");
  });
  it("rejects a short title", () => {
    expect(createTicketSchema.safeParse({ title: "ab", body: "x" }).success).toBe(false);
  });
  it("rejects a blank body", () => {
    expect(createTicketSchema.safeParse({ title: "abc", body: "   " }).success).toBe(false);
  });
  it("rejects missing fields", () => {
    expect(createTicketSchema.safeParse({}).success).toBe(false);
  });
});

describe("listQuerySchema", () => {
  it("applies defaults", () => {
    expect(listQuerySchema.parse({}).limit).toBe(20);
  });
  it("coerces numeric strings from the query string", () => {
    const r = listQuerySchema.parse({ cursor: "42", limit: "5" });
    expect(r).toMatchObject({ cursor: 42, limit: 5 });
  });
  it("rejects an unknown status and an oversized limit", () => {
    expect(listQuerySchema.safeParse({ status: "DONE" }).success).toBe(false);
    expect(listQuerySchema.safeParse({ limit: "1000" }).success).toBe(false);
  });
});
