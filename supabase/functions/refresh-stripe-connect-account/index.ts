import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

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
    if (!stripeSecretKey) throw new Error("configuration_error");

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
    const context = Array.isArray(data) ? data[0] : data;
    const gymId = context?.gym_id?.toString();
    const stripeAccountId = context?.stripe_account_id?.toString();
    if (!gymId || !stripeAccountId) throw new Error("missing_connect_context");

    const stripeResponse = await fetch(
      `https://api.stripe.com/v1/accounts/${
        encodeURIComponent(stripeAccountId)
      }`,
      { headers: { Authorization: `Bearer ${stripeSecretKey}` } },
    );
    const account = await stripeResponse.json();
    if (!stripeResponse.ok) throw new Error("stripe_request_failed");

    const chargesEnabled = account.charges_enabled === true;
    const payoutsEnabled = account.payouts_enabled === true;
    const detailsSubmitted = account.details_submitted === true;

    const { error: updateError } = await adminClient
      .from("gyms")
      .update({
        stripe_onboarding_complete: detailsSubmitted,
        stripe_charges_enabled: chargesEnabled,
        stripe_payouts_enabled: payoutsEnabled,
      })
      .eq("id", gymId)
      .eq("stripe_account_id", stripeAccountId);
    if (updateError) throw updateError;

    console.log(JSON.stringify({
      operation: "stripe_connect_status_refreshed",
      gymId,
      stripeAccountId,
      detailsSubmitted,
      chargesEnabled,
      payoutsEnabled,
    }));

    return new Response(
      JSON.stringify({
        ok: true,
        stripeAccountId,
        onboardingComplete: detailsSubmitted,
        chargesEnabled,
        payoutsEnabled,
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
