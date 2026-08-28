export function assertGymOperational(status: unknown) {
  if (status !== "active") throw new Error("Gym is not active");
}

export function assertEffectiveGymSelection(
  profileGymId: unknown,
  effectiveGymId: unknown,
) {
  if (!profileGymId || profileGymId !== effectiveGymId) {
    throw new Error("Admin has no active effective gym");
  }
}
