import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  canInviteAthlete,
  canReuseExistingProfile,
  gymMemberRelation,
  invitedMemberRole,
} from "./logic.ts";

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

    const body = await req.json();
    const email = String(body.email ?? "").trim().toLowerCase();
    const fullName = String(body.full_name ?? body.fullName ?? "").trim();
    const phone = String(body.phone ?? "").trim();
    const birthDate = String(body.birth_date ?? body.birthDate ?? "").trim();
    const role = String(body.role ?? "athlete").trim().toLowerCase();
    const redirectTo = String(body.redirectTo ?? "").trim() ||
      "athletelab://reset-password";

    if (!email) throw new Error("Missing email");

    const [
      { data: effectiveGymId, error: gymError },
      { data: effectiveRole, error: roleError },
    ] = await Promise.all([
      userClient.rpc("effective_gym_id"),
      userClient.rpc("effective_gym_role"),
    ]);
    if (gymError) throw gymError;
    if (roleError) throw roleError;
    if (!canInviteAthlete(effectiveRole)) {
      throw new Error("Only admins can invite athletes");
    }
    if (!effectiveGymId) throw new Error("Admin has no effective gym");

    let { data, error } = await adminClient.auth.admin.inviteUserByEmail(
      email,
      {
        data: {
          full_name: fullName || email,
          phone: phone || null,
          birth_date: birthDate || null,
          role: invitedMemberRole(role),
          gym_id: effectiveGymId,
        },
        redirectTo,
      },
    );

    if (error) {
      const { data: existingProfile, error: existingError } = await adminClient
        .from("profiles")
        .select("id, gym_id")
        .eq("email", email)
        .maybeSingle();
      if (existingError) throw existingError;
      if (
        !existingProfile ||
        !canReuseExistingProfile(existingProfile.gym_id, effectiveGymId)
      ) {
        throw error;
      }
      data = { user: { id: existingProfile.id } } as typeof data;
      error = null;
    }

    if (data.user?.id && (phone || birthDate || fullName)) {
      await adminClient
        .from("profiles")
        .update({
          full_name: fullName || email,
          phone: phone || null,
          birth_date: birthDate || null,
        })
        .eq("id", data.user.id);
    }

    if (!data.user?.id) throw new Error("Invitation did not resolve a user");

    const relation = gymMemberRelation({
      gymId: effectiveGymId,
      userId: data.user.id,
      role,
      invitedBy: userData.user.id,
      joinedAt: new Date().toISOString(),
    });
    const { error: insertRelationError } = await adminClient
      .from("gym_members")
      .upsert(relation, {
        onConflict: "gym_id,user_id",
        ignoreDuplicates: true,
      });
    if (insertRelationError) throw insertRelationError;
    const { error: relationError } = await adminClient
      .from("gym_members")
      .update({
        role: relation.role,
        is_active: relation.is_active,
        is_coach: relation.is_coach,
        invited_by: relation.invited_by,
      })
      .eq("gym_id", effectiveGymId)
      .eq("user_id", data.user.id);
    if (relationError) throw relationError;

    return new Response(JSON.stringify({ ok: true, user: data.user }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: e instanceof Error ? e.message : String(e),
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
