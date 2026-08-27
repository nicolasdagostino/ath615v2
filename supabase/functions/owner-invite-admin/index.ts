import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  ownerCanInvite,
  ownerInviteMetadata,
  shouldMaterializeInvitedName,
} from "./logic.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: auth, error: authError } = await userClient.auth.getUser();
    if (authError || !auth.user) throw new Error("Unauthorized");
    const body = await req.json();
    const email = String(body.email ?? "").trim().toLowerCase();
    const fullName = String(body.full_name ?? body.fullName ?? "").trim();
    if (!email) throw new Error("Missing email");

    const [
      { data: gymId, error: gymError },
      { data: profile, error: profileError },
    ] = await Promise.all([
      userClient.rpc("effective_gym_id"),
      admin.from("profiles").select("role").eq("id", auth.user.id).single(),
    ]);
    if (gymError || !gymId) throw gymError ?? new Error("No effective gym");
    if (profileError) throw profileError;
    const { data: gym, error: gymLookupError } = await admin.from("gyms")
      .select("owner_id").eq("id", gymId).single();
    if (gymLookupError) throw gymLookupError;
    if (
      !ownerCanInvite({
        profileRole: profile.role,
        gymOwnerId: gym.owner_id,
        actorId: auth.user.id,
      })
    ) throw new Error("Only the gym owner can invite admins");

    let { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { ...ownerInviteMetadata(fullName), gym_id: gymId },
      redirectTo: "athletelab://reset-password",
    });
    if (error) {
      const { data: existing, error: existingError } = await admin.from(
        "profiles",
      ).select("id,full_name").eq("email", email).maybeSingle();
      if (existingError || !existing) throw existingError ?? error;
      data = { user: { id: existing.id } } as typeof data;
    }
    if (!data.user?.id) throw new Error("Invitation did not resolve a user");
    const { data: current, error: currentError } = await admin.from("profiles")
      .select("full_name").eq("id", data.user.id).single();
    if (currentError) throw currentError;
    if (shouldMaterializeInvitedName(current.full_name, fullName)) {
      await admin.from("profiles").update({ full_name: fullName }).eq(
        "id",
        data.user.id,
      );
    }
    const relation = {
      gym_id: gymId,
      user_id: data.user.id,
      role: "admin",
      is_active: true,
      is_coach: false,
      joined_at: new Date().toISOString(),
      invited_by: auth.user.id,
    };
    const { error: relationError } = await admin.from("gym_members").upsert(
      relation,
      { onConflict: "gym_id,user_id", ignoreDuplicates: true },
    );
    if (relationError) throw relationError;
    await admin.from("gym_members").update({
      role: "admin",
      is_active: true,
      is_coach: false,
      invited_by: auth.user.id,
    }).eq("gym_id", gymId).eq("user_id", data.user.id);
    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
