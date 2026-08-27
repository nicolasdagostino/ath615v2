export function ownerCanInvite(
  input: { profileRole: unknown; gymOwnerId: unknown; actorId: string },
) {
  return input.profileRole === "owner" && input.gymOwnerId === input.actorId;
}

export function ownerInviteMetadata(fullName: string) {
  const normalized = fullName.trim();
  return normalized
    ? { full_name: normalized, role: "admin" }
    : { role: "admin" };
}

export function shouldMaterializeInvitedName(
  existing: unknown,
  invited: string,
) {
  return String(existing ?? "").trim() === "" && invited.trim() !== "";
}
