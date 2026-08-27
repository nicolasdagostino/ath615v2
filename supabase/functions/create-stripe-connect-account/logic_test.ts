import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import { stripeConnectRefreshUrl, stripeConnectReturnUrl } from "./logic.ts";

Deno.test("Stripe Connect uses the two narrow HTTPS universal links", () => {
  assertEquals(
    stripeConnectReturnUrl,
    "https://athlete615.com/connect/stripe/return",
  );
  assertEquals(
    stripeConnectRefreshUrl,
    "https://athlete615.com/connect/stripe/refresh",
  );
});
