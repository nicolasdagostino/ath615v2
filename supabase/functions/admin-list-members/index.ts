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

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) throw new Error("Unauthorized");

    const { data: adminProfile, error: adminError } = await adminClient
      .from("profiles")
      .select("role, gym_id")
      .eq("id", userData.user.id)
      .single();

    if (adminError) throw adminError;
    if (adminProfile.role !== "admin" && adminProfile.role !== "owner") {
      throw new Error("Only admins can list members");
    }
    if (!adminProfile.gym_id) throw new Error("Admin has no gym_id");

    const { data: profiles, error: profilesError } = await adminClient
      .from("profiles")
      .select(
        "id, full_name, email, role, gym_id, phone, birth_date, avatar_url, is_active, created_at",
      )
      .eq("gym_id", adminProfile.gym_id)
      .neq("role", "owner")
      .order("created_at", { ascending: false });

    if (profilesError) throw profilesError;

    const userIds = (profiles ?? []).map((profile) => profile.id);

    const { data: gymMembers, error: gymMembersError } = userIds.length
      ? await adminClient
        .from("gym_members")
        .select("user_id, created_at")
        .eq("gym_id", adminProfile.gym_id)
        .in("user_id", userIds)
      : { data: [], error: null };

    if (gymMembersError) throw gymMembersError;

    const gymMemberCreatedAtByUserId = new Map(
      (gymMembers ?? []).map((gymMember) => [
        gymMember.user_id,
        gymMember.created_at,
      ]),
    );

    const { data: memberships, error: membershipsError } = userIds.length
      ? await adminClient
        .from("member_memberships")
        .select(
          "user_id, credits_remaining, expires_at, membership_plans(name, plan_type, price, currency, duration_days)",
        )
        .in("user_id", userIds)
        .eq("is_active", true)
        .eq("status", "active")
        .order("created_at", { ascending: false })
      : { data: [], error: null };

    if (membershipsError) throw membershipsError;

    const now = Date.now();
    const membershipByUserId = new Map();

    for (const membership of memberships ?? []) {
      const userId = membership.user_id;
      const expiresAt = membership.expires_at
        ? Date.parse(membership.expires_at)
        : null;
      const creditsRemaining = membership.credits_remaining;

      const isValid = (expiresAt === null || expiresAt > now) &&
        (creditsRemaining === null || creditsRemaining > 0);

      if (!isValid) continue;

      if (!membershipByUserId.has(userId)) {
        membershipByUserId.set(userId, membership);
      }
    }

    const members = [];

    for (const profile of profiles ?? []) {
      const { data: authUser } = await adminClient.auth.admin.getUserById(
        profile.id,
      );

      const authEmail = authUser.user?.email ?? null;
      const emailConfirmedAt = authUser.user?.email_confirmed_at ?? null;
      const lastSignInAt = authUser.user?.last_sign_in_at ?? null;
      const membership = membershipByUserId.get(profile.id) ?? null;
      const membershipPlan = membership?.membership_plans ?? null;

      const invitationStatus = !profile.is_active
        ? "disabled"
        : emailConfirmedAt || lastSignInAt
        ? "active"
        : "pending";

      members.push({
        ...profile,
        email: profile.email ?? authEmail,
        auth_email: authEmail,
        email_confirmed_at: emailConfirmedAt,
        last_sign_in_at: lastSignInAt,
        invitation_status: invitationStatus,
        gym_member_created_at: gymMemberCreatedAtByUserId.get(profile.id) ??
          null,
        membership_name: membershipPlan?.name ?? null,
        membership_type: membershipPlan?.plan_type ?? null,
        membership_price: membershipPlan?.price ?? null,
        membership_currency: membershipPlan?.currency ?? null,
        membership_duration_days: membershipPlan?.duration_days ?? null,
        credits_remaining: membership?.credits_remaining ?? null,
        membership_expires_at: membership?.expires_at ?? null,
      });
    }

    return new Response(JSON.stringify({ ok: true, members }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    const errorMessage = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ ok: false, error: errorMessage }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
