import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildCheckoutSessionParams,
  type CheckoutContext,
  checkoutDocumentIds,
  checkoutIdempotencyKey,
} from "./index.ts";

const context: CheckoutContext = {
  request_id: "request-1",
  gym_id: "gym-a",
  plan_id: "plan-a",
  plan_name: "5 Classes",
  amount_total: 4995,
  currency: "eur",
  stripe_account_id: "acct_a",
};

Deno.test("checkout idempotency key is stable for one acquisition", () => {
  assertEquals(
    checkoutIdempotencyKey(context.request_id),
    "membership-checkout:request-1",
  );
  assertEquals(
    checkoutIdempotencyKey(context.request_id),
    checkoutIdempotencyKey(context.request_id),
  );
});

Deno.test("checkout amount and gym metadata come from server context", () => {
  const params = buildCheckoutSessionParams(
    context,
    "user-a",
    "member@example.test",
    1_800_000_000,
  );

  assertEquals(
    params.get("line_items[0][price_data][unit_amount]"),
    "4995",
  );
  assertEquals(params.get("line_items[0][price_data][currency]"), "eur");
  assertEquals(params.get("metadata[gym_id]"), "gym-a");
  assertEquals(params.get("metadata[plan_id]"), "plan-a");
  assertEquals(params.get("metadata[user_id]"), "user-a");
  assertEquals(params.get("metadata[request_id]"), "request-1");
  assertEquals(params.get("payment_method_types[0]"), "card");
});

Deno.test("checkout normalizes document ids for server-side acceptance", () => {
  assertEquals(checkoutDocumentIds([" terms-id ", "", "waiver-id"]), [
    "terms-id",
    "waiver-id",
  ]);
  assertEquals(checkoutDocumentIds("terms-id"), []);
});

Deno.test("invalid server-side plan price is rejected", () => {
  assertThrows(
    () =>
      buildCheckoutSessionParams(
        { ...context, amount_total: 0 },
        "user-a",
        null,
        1_800_000_000,
      ),
    Error,
    "invalid_plan_price",
  );
});
