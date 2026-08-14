import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "npm:stripe@22.5.0";

type WebhookEvent = Stripe.Event;

const stripeCryptoProvider = Stripe.createSubtleCryptoProvider();

export async function constructStripeWebhookEvent(
  body: string,
  signature: string | null,
  webhookSecret: string,
): Promise<WebhookEvent> {
  if (!signature) throw new Error("missing_signature");

  const verifier = new Stripe("sk_test_signature_verification_only");
  return await verifier.webhooks.constructEventAsync(
    body,
    signature,
    webhookSecret,
    undefined,
    stripeCryptoProvider,
  );
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function safeLog(
  event: Partial<WebhookEvent>,
  stripeAccountId: string | null,
  gymId: string | null,
  result: string,
) {
  console.log(JSON.stringify({
    eventId: event.id ?? null,
    eventType: event.type ?? null,
    stripeAccountId,
    gymId,
    result,
  }));
}

export async function handleStripeWebhook(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");

  if (!webhookSecret) {
    return jsonResponse({ ok: false, error: "configuration_error" }, 500);
  }

  const body = await req.text();
  let event: WebhookEvent;

  try {
    event = await constructStripeWebhookEvent(
      body,
      req.headers.get("stripe-signature"),
      webhookSecret,
    );
  } catch (_) {
    safeLog({}, null, null, "invalid_signature");
    return jsonResponse({ ok: false, error: "invalid_signature" }, 400);
  }

  const stripeAccountId = event.account?.toString() ?? null;
  if (!stripeAccountId) {
    safeLog(event, null, null, "missing_connected_account");
    return jsonResponse(
      { ok: false, error: "missing_connected_account" },
      400,
    );
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  let gymId: string | null = null;
  let claimed = false;

  try {
    const { data: claimRows, error: claimError } = await adminClient.rpc(
      "claim_stripe_webhook_event",
      {
        p_event_id: event.id,
        p_event_type: event.type,
        p_stripe_account_id: stripeAccountId,
      },
    );
    if (claimError) throw claimError;

    const claim = Array.isArray(claimRows) ? claimRows[0] : claimRows;
    claimed = claim?.claimed === true;
    gymId = claim?.gym_id?.toString() ?? null;

    if (!claimed) {
      safeLog(event, stripeAccountId, gymId, "duplicate");
      return jsonResponse({ ok: true, duplicate: true });
    }

    if (
      event.type !== "checkout.session.completed" &&
      event.type !== "checkout.session.expired"
    ) {
      const { error } = await adminClient.rpc(
        "complete_stripe_webhook_event",
        {
          p_event_id: event.id,
          p_stripe_account_id: stripeAccountId,
          p_status: "ignored",
          p_error_code: null,
        },
      );
      if (error) throw error;
      safeLog(event, stripeAccountId, gymId, "ignored");
      return jsonResponse({ ok: true, ignored: true });
    }

    const session = event.data.object as Stripe.Checkout.Session;
    if (!session.id) throw new Error("missing_checkout_session");

    if (event.type === "checkout.session.completed") {
      if (session.payment_status !== "paid") {
        throw new Error("checkout_not_paid");
      }

      const { error } = await adminClient.rpc(
        "complete_card_membership_request",
        {
          p_checkout_session_id: session.id,
          p_payment_intent_id: typeof session.payment_intent === "string"
            ? session.payment_intent
            : session.payment_intent?.id ?? null,
          p_amount_total: session.amount_total ?? null,
          p_currency: session.currency ?? null,
          p_stripe_account_id: stripeAccountId,
        },
      );
      if (error) throw error;
    } else {
      const { error } = await adminClient.rpc(
        "cancel_expired_card_membership_request",
        {
          p_checkout_session_id: session.id,
          p_stripe_account_id: stripeAccountId,
        },
      );
      if (error) throw error;
    }

    const { error: completionError } = await adminClient.rpc(
      "complete_stripe_webhook_event",
      {
        p_event_id: event.id,
        p_stripe_account_id: stripeAccountId,
        p_status: "processed",
        p_error_code: null,
      },
    );
    if (completionError) throw completionError;

    safeLog(event, stripeAccountId, gymId, "processed");
    return jsonResponse({ ok: true });
  } catch (_) {
    if (claimed) {
      await adminClient.rpc("complete_stripe_webhook_event", {
        p_event_id: event.id,
        p_stripe_account_id: stripeAccountId,
        p_status: "failed",
        p_error_code: "processing_failed",
      });
    }
    safeLog(event, stripeAccountId, gymId, "processing_failed");
    return jsonResponse({ ok: false, error: "processing_failed" }, 500);
  }
}

if (import.meta.main) {
  serve(handleStripeWebhook);
}
