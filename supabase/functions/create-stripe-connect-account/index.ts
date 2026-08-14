import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

type ConnectContext = {
  gym_id: string;
  gym_name: string;
  gym_email?: string | null;
  business_name?: string | null;
  stripe_account_id?: string | null;
};

async function stripeRequest(
  path: string,
  secretKey: string,
  params: Record<string, string>,
  idempotencyKey?: string,
) {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${secretKey}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;

  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: "POST",
    headers,
    body: new URLSearchParams(params),
  });
  const json = await response.json();
  if (!response.ok) {
    throw new Error(json?.error?.code ?? "stripe_request_failed");
  }
  return json;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    const refreshUrl = Deno.env.get("STRIPE_CONNECT_REFRESH_URL");
    const returnUrl = Deno.env.get("STRIPE_CONNECT_RETURN_URL");

    if (!stripeSecretKey || !refreshUrl || !returnUrl) {
      throw new Error("configuration_error");
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) throw new Error("unauthorized");

    const { data, error } = await userClient.rpc(
      "get_effective_stripe_connect_context",
    );
    if (error) throw error;
    const context = (Array.isArray(data) ? data[0] : data) as ConnectContext;
    if (!context?.gym_id) throw new Error("missing_connect_context");

    let stripeAccountId = context.stripe_account_id ?? null;
    if (!stripeAccountId) {
      const account = await stripeRequest(
        "accounts",
        stripeSecretKey,
        {
          type: "express",
          country: "ES",
          email: String(context.gym_email ?? userData.user.email ?? ""),
          "capabilities[card_payments][requested]": "true",
          "capabilities[transfers][requested]": "true",
          "business_profile[name]": String(
            context.business_name ?? context.gym_name ?? "ATHLETE615 Gym",
          ),
          "metadata[gym_id]": context.gym_id,
        },
        `stripe-connect-account:${context.gym_id}`,
      );
      stripeAccountId = account.id;

      const { error: updateError } = await adminClient
        .from("gyms")
        .update({
          stripe_account_id: stripeAccountId,
          stripe_onboarding_complete: false,
          stripe_charges_enabled: false,
          stripe_payouts_enabled: false,
        })
        .eq("id", context.gym_id)
        .is("stripe_account_id", null);
      if (updateError) throw updateError;
    }

    if (!stripeAccountId) throw new Error("missing_stripe_account");
    const resolvedStripeAccountId = stripeAccountId;

    const accountLink = await stripeRequest(
      "account_links",
      stripeSecretKey,
      {
        account: resolvedStripeAccountId,
        refresh_url: refreshUrl,
        return_url: returnUrl,
        type: "account_onboarding",
      },
    );

    console.log(JSON.stringify({
      operation: "stripe_connect_onboarding_created",
      gymId: context.gym_id,
      stripeAccountId: resolvedStripeAccountId,
    }));

    return new Response(
      JSON.stringify({
        ok: true,
        url: accountLink.url,
        stripeAccountId: resolvedStripeAccountId,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (_) {
    return new Response(
      JSON.stringify({ ok: false, error: "stripe_connect_unavailable" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
