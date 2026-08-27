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
