// Root layout: wraps every page. Server Component by default (no client JS shipped).
import type { ReactNode } from "react";

export const metadata = { title: "Helpdesk" };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", maxWidth: 720, margin: "2rem auto", padding: "0 1rem" }}>
        <nav style={{ marginBottom: "1.5rem" }}>
          <a href="/">Tickets</a> · <a href="/tickets/new">New ticket</a>
        </nav>
        {children}
      </body>
    </html>
  );
}
