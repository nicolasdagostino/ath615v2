import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  canInviteAthlete,
  canReuseExistingProfile,
  cleanupFailedInvite,
  gymMemberRelation,
  invitedMemberRole,
  invitedProfilePatch,
  publicInviteError,
} from "./logic.ts";

type ReservationClient = {
  rpc: (name: string, params: Record<string, unknown>) => Promise<unknown>;
};
type CleanupAdminClient = {
  auth: { admin: { deleteUser: (id: string) => Promise<unknown> } };
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let reservationId: string | null = null;
  let createdAuthUserId: string | null = null;
  let reservationClient: ReservationClient | null = null;
  let cleanupAdminClient: CleanupAdminClient | null = null;
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    reservationClient = userClient as unknown as ReservationClient;
    cleanupAdminClient = adminClient as unknown as CleanupAdminClient;

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

    // Reserve capacity transactionally before Auth Admin can create/send
    // anything. The reservation protects this slot across service boundaries.
    if (invitedMemberRole(role) === "athlete") {
      const { data: reservedId, error: slotError } = await userClient.rpc(
        "reserve_effective_gym_athlete_slot",
        { p_email: email },
      );
      if (slotError) throw slotError;
      reservationId = String(reservedId);
    }

    let { data, error } = await adminClient.auth.admin.inviteUserByEmail(
      email,
      {
        data: {
          ...(fullName ? { full_name: fullName } : {}),
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
        .select("id, gym_id, full_name")
        .eq("email", email)
        .maybeSingle();
      if (existingError) throw existingError;
      if (
        !existingProfile ||
        !canReuseExistingProfile(existingProfile.id)
      ) {
        throw error;
      }
      data = { user: { id: existingProfile.id } } as typeof data;
      error = null;
    } else if (data.user?.id) {
      createdAuthUserId = data.user.id;
    }

    if (data.user?.id && (phone || birthDate || fullName)) {
      const { data: currentProfile, error: currentProfileError } =
        await adminClient.from("profiles").select("full_name").eq(
          "id",
          data.user.id,
        ).single();
      if (currentProfileError) throw currentProfileError;
      const profilePatch = invitedProfilePatch({
        existingFullName: currentProfile.full_name,
        invitedFullName: fullName,
        phone,
        birthDate,
      });
      if (Object.keys(profilePatch).length > 0) {
        await adminClient
          .from("profiles")
          .update(profilePatch)
          .eq("id", data.user.id);
      }
    }

    if (!data.user?.id) throw new Error("Invitation did not resolve a user");

    if (invitedMemberRole(role) === "athlete") {
      const { error: materializeError } = await adminClient.rpc(
        "materialize_reserved_gym_athlete",
        {
          p_reservation_id: reservationId,
          p_user_id: data.user.id,
          p_invited_by: userData.user.id,
        },
      );
      if (materializeError) throw materializeError;
      reservationId = null;
    } else {
      const relation = gymMemberRelation({
        gymId: effectiveGymId,
        userId: data.user.id,
        role,
        invitedBy: userData.user.id,
        joinedAt: new Date().toISOString(),
      });
      const { error: relationError } = await adminClient.from("gym_members")
        .upsert(relation, { onConflict: "gym_id,user_id" });
      if (relationError) throw relationError;
    }

    return new Response(JSON.stringify({ ok: true, user: data.user }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    await cleanupFailedInvite({
      createdAuthUserId,
      reservationId,
      deleteCreatedUser: (id) => cleanupAdminClient!.auth.admin.deleteUser(id),
      releaseReservation: (id) =>
        reservationClient!.rpc(
          "release_gym_athlete_slot_reservation",
          { p_reservation_id: id },
        ),
    });
    const publicError = publicInviteError(e);
    return new Response(
      JSON.stringify({
        ok: false,
        error: publicError.error,
        code: publicError.code,
      }),
      {
        status: publicError.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
