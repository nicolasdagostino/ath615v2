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
  existingGymId: unknown,
  effectiveGymId: string,
): boolean {
  return existingGymId === effectiveGymId;
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
