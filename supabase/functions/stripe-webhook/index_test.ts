import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import Stripe from "npm:stripe@22.5.0";
import {
  constructStripeWebhookEvent,
  stripeCheckoutEventAction,
} from "./index.ts";

const secret = "whsec_test_secret";
const payload = JSON.stringify({
  id: "evt_test",
  object: "event",
  type: "checkout.session.completed",
  account: "acct_test",
  data: { object: { id: "cs_test", object: "checkout.session" } },
});

async function signatureHeader(timestamp: number, overridePayload = payload) {
  return await Stripe.webhooks.generateTestHeaderStringAsync({
    payload: overridePayload,
    secret,
    timestamp,
  });
}

Deno.test("official Stripe verifier accepts a valid raw payload", async () => {
  const event = await constructStripeWebhookEvent(
    payload,
    await signatureHeader(Math.floor(Date.now() / 1000)),
    secret,
  );
  assertEquals(event.id, "evt_test");
  assertEquals(event.account, "acct_test");
});

Deno.test("official Stripe verifier rejects invalid signatures", async () => {
  const signature = await signatureHeader(
    Math.floor(Date.now() / 1000),
    `${payload}tampered`,
  );
  await assertRejects(
    () =>
      constructStripeWebhookEvent(
        payload,
        signature,
        secret,
      ),
    Error,
  );
});

Deno.test("official Stripe verifier rejects old signed payloads", async () => {
  const signature = await signatureHeader(
    Math.floor(Date.now() / 1000) - 3600,
  );
  await assertRejects(
    () =>
      constructStripeWebhookEvent(
        payload,
        signature,
        secret,
      ),
    Error,
  );
});

Deno.test("official Stripe verifier accepts any valid v1 signature", async () => {
  const valid = await signatureHeader(Math.floor(Date.now() / 1000));
  const timestamp = valid.match(/t=([^,]+)/)?.[1];
  const v1 = valid.match(/v1=([^,]+)/)?.[1];
  const combined = `t=${timestamp},v1=invalid,v1=${v1}`;
  const event = await constructStripeWebhookEvent(payload, combined, secret);
  assertEquals(event.id, "evt_test");
});

Deno.test("checkout lifecycle never treats unpaid completion as success", () => {
  assertEquals(
    stripeCheckoutEventAction("checkout.session.completed", "unpaid"),
    "pending",
  );
  assertEquals(
    stripeCheckoutEventAction("checkout.session.completed", "paid"),
    "complete",
  );
  assertEquals(
    stripeCheckoutEventAction(
      "checkout.session.async_payment_succeeded",
      "paid",
    ),
    "complete",
  );
  assertEquals(
    stripeCheckoutEventAction(
      "checkout.session.async_payment_failed",
      "unpaid",
    ),
    "fail",
  );
  assertEquals(
    stripeCheckoutEventAction("checkout.session.expired", "unpaid"),
    "expire",
  );
});
