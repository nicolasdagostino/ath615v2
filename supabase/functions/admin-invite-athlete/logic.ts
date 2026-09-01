export function canInviteAthlete(role: unknown): boolean {
  return role === "admin" || role === "owner";
}

export function invitedMemberRole(
  role: unknown,
): "admin" | "coach" | "athlete" {
  return role === "admin" || role === "coach" || role === "athlete"
    ? role
    : "athlete";
}

export function canReuseExistingProfile(
  existingProfileId: unknown,
): boolean {
  return typeof existingProfileId === "string" && existingProfileId.length > 0;
}

export function invitedProfilePatch(input: {
  existingFullName: unknown;
  invitedFullName: string;
  phone: string;
  birthDate: string;
}) {
  const patch: Record<string, string> = {};
  if (
    String(input.existingFullName ?? "").trim().length === 0 &&
    input.invitedFullName.trim().length > 0
  ) patch.full_name = input.invitedFullName.trim();
  if (input.phone.trim()) patch.phone = input.phone.trim();
  if (input.birthDate.trim()) patch.birth_date = input.birthDate.trim();
  return patch;
}

export function gymMemberRelation(input: {
  gymId: string;
  userId: string;
  role: unknown;
  invitedBy: string;
  joinedAt: string;
}) {
  const role = invitedMemberRole(input.role);
  return {
    gym_id: input.gymId,
    user_id: input.userId,
    role,
    is_active: true,
    is_coach: role === "coach",
    joined_at: input.joinedAt,
    invited_by: input.invitedBy,
  };
}

export function publicInviteError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const code = message.includes("gym_member_limit_reached")
    ? "gym_member_limit_reached"
    : null;
  return { code, error: code ?? "request_failed", status: code ? 409 : 400 };
}

export async function cleanupFailedInvite(input: {
  createdAuthUserId: string | null;
  reservationId: string | null;
  deleteCreatedUser: (id: string) => Promise<unknown>;
  releaseReservation: (id: string) => Promise<unknown>;
}) {
  if (input.createdAuthUserId) {
    try {
      await input.deleteCreatedUser(input.createdAuthUserId);
    } catch (_) {
      // Best effort; never delete an identity not created by this request.
    }
  }
  if (input.reservationId) {
    try {
      await input.releaseReservation(input.reservationId);
    } catch (_) {
      // Expiry is the final reservation cleanup fallback.
    }
  }
}
