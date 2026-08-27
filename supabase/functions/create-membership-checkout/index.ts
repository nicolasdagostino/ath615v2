import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

export type CheckoutContext = {
  request_id: string;
  gym_id: string;
  plan_id: string;
  plan_name: string;
  amount_total: number;
  currency: string;
  stripe_account_id: string;
  existing_session_id?: string | null;
  existing_session_expires_at?: string | null;
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function checkoutIdempotencyKey(requestId: string) {
  return `membership-checkout:${requestId}`;
}

export function checkoutDocumentIds(value: unknown): string[] {
  return Array.isArray(value)
    ? value.map((item) => String(item).trim()).filter(Boolean)
    : [];
}

export function checkoutSafeErrorCode(error: unknown) {
  return String(
      (error as { message?: unknown })?.message ?? error ?? "",
    ).includes("documents_changed")
    ? "documents_changed"
    : "checkout_unavailable";
}

export function buildCheckoutSessionParams(
  context: CheckoutContext,
  userId: string,
  email: string | null,
  expiresAt: number,
) {
  const unitAmount = Number(context.amount_total);
  if (!Number.isSafeInteger(unitAmount) || unitAmount <= 0) {
    throw new Error("invalid_plan_price");
  }

  const params = new URLSearchParams();
  params.set("mode", "payment");
  // v2 lifecycle is intentionally card-only. This keeps completion synchronous;
  // Checkout cannot silently add an asynchronous payment method.
  params.set("payment_method_types[0]", "card");
  params.set("expires_at", expiresAt.toString());
  params.set(
    "success_url",
    "athletelab://checkout?status=success&session_id={CHECKOUT_SESSION_ID}",
  );
  params.set("cancel_url", "athletelab://checkout?status=cancel");
  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", context.currency);
  params.set(
    "line_items[0][price_data][unit_amount]",
    unitAmount.toString(),
  );
  params.set(
    "line_items[0][price_data][product_data][name]",
    context.plan_name,
  );
  params.set("metadata[request_id]", context.request_id);
  params.set("metadata[user_id]", userId);
  params.set("metadata[gym_id]", context.gym_id);
  params.set("metadata[plan_id]", context.plan_id);

  if (email) params.set("customer_email", email);
  return params;
}

async function stripeRequest(
  path: string,
  stripeSecretKey: string,
  stripeAccountId: string,
  init: RequestInit = {},
) {
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${stripeSecretKey}`,
      "Stripe-Account": stripeAccountId,
      ...init.headers,
    },
  });
  const json = await response.json();
  if (!response.ok) {
    throw new Error(json?.error?.code ?? "stripe_request_failed");
  }
  return json;
}

export async function handleCreateMembershipCheckout(
  req: Request,
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeSecretKey) throw new Error("configuration_error");

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) throw new Error("unauthorized");

    const body = await req.json();
    const planId = String(body.planId ?? "").trim();
    if (!planId) throw new Error("missing_plan_id");
    const documentIds = checkoutDocumentIds(body.documentIds);
    const gymDocumentVersionIds = checkoutDocumentIds(
      body.gymDocumentVersionIds,
    );

    const { error: consentError } = await userClient.rpc(
      "accept_membership_checkout_document_snapshot",
      {
        p_plan_id: planId,
        p_document_ids: documentIds,
        p_gym_document_version_ids: gymDocumentVersionIds,
      },
    );
    if (consentError) throw consentError;

    const prepare = async (): Promise<CheckoutContext> => {
      const { data, error } = await userClient.rpc(
        "prepare_card_membership_checkout",
        { p_plan_id: planId },
      );
      if (error) throw error;
      const context = Array.isArray(data) ? data[0] : data;
      if (!context?.request_id || !context?.stripe_account_id) {
        throw new Error("missing_checkout_context");
      }
      return context as CheckoutContext;
    };

    let context = await prepare();

    if (context.existing_session_id) {
      const existing = await stripeRequest(
        `checkout/sessions/${encodeURIComponent(context.existing_session_id)}`,
        stripeSecretKey,
        context.stripe_account_id,
      );

      if (existing.status === "open" && existing.url) {
        return jsonResponse({
          ok: true,
          url: existing.url,
          sessionId: existing.id,
          reused: true,
        });
      }

      if (existing.status === "expired") {
        const { error } = await adminClient.rpc(
          "cancel_expired_card_membership_request",
          {
            p_checkout_session_id: context.existing_session_id,
            p_stripe_account_id: context.stripe_account_id,
          },
        );
        if (error) throw error;
        context = await prepare();
      } else {
        throw new Error("checkout_already_completed");
      }
    }

    const expiresAt = Math.floor(Date.now() / 1000 + 60 * 60);
    const params = buildCheckoutSessionParams(
      context,
      userData.user.id,
      userData.user.email ?? null,
      expiresAt,
    );

    const session = await stripeRequest(
      "checkout/sessions",
      stripeSecretKey,
      context.stripe_account_id,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Idempotency-Key": checkoutIdempotencyKey(context.request_id),
        },
        body: params,
      },
    );

    if (!session.id || !session.url || session.amount_total == null) {
      throw new Error("invalid_checkout_session");
    }

    const { error: attachError } = await adminClient.rpc(
      "attach_card_membership_checkout_session",
      {
        p_request_id: context.request_id,
        p_checkout_session_id: session.id,
        p_amount_total: session.amount_total,
        p_currency: session.currency,
        p_stripe_account_id: context.stripe_account_id,
        p_expires_at: new Date(expiresAt * 1000).toISOString(),
      },
    );
    if (attachError) throw attachError;

    console.log(JSON.stringify({
      operation: "membership_checkout_created",
      requestId: context.request_id,
      gymId: context.gym_id,
      stripeAccountId: context.stripe_account_id,
      sessionId: session.id,
    }));

    return jsonResponse({ ok: true, url: session.url, sessionId: session.id });
  } catch (error) {
    const safeCode = checkoutSafeErrorCode(error);
    return jsonResponse(
      { ok: false, error: safeCode },
      safeCode === "documents_changed" ? 409 : 400,
    );
  }
}

if (import.meta.main) {
  serve(handleCreateMembershipCheckout);
}
