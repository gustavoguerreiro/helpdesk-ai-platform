// Input validation shared by the route handler (API) and the Server Action (form).
// One schema, two entry points: the rules cannot drift apart.
// Never trust input from the browser, even from our own form.
import { z } from "zod";

export const createTicketSchema = z.object({
  title: z.string().trim().min(3, "Title needs at least 3 characters").max(120),
  body: z.string().trim().min(1, "Describe the problem").max(5000),
});

export type CreateTicketInput = z.infer<typeof createTicketSchema>;

// Query string for the list endpoint: ?status=OPEN&cursor=42&limit=20
export const listQuerySchema = z.object({
  status: z.enum(["OPEN", "IN_PROGRESS", "CLOSED"]).optional(),
  // Cursor pagination: "give me tickets older than this id". Unlike OFFSET it
  // stays fast on deep pages and does not skip/repeat rows when data changes.
  cursor: z.coerce.number().int().positive().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
