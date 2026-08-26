import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  canInviteAthlete,
  canReuseExistingProfile,
  gymMemberRelation,
  invitedMemberRole,
} from "./logic.ts";

Deno.test("only an effective owner or admin can invite", () => {
  assertEquals(canInviteAthlete("owner"), true);
  assertEquals(canInviteAthlete("admin"), true);
  assertEquals(canInviteAthlete("coach"), false);
  assertEquals(canInviteAthlete("athlete"), false);
});

Deno.test("an existing profile is reusable only inside the effective gym", () => {
  assertEquals(canReuseExistingProfile("gym-a", "gym-a"), true);
  assertEquals(canReuseExistingProfile("gym-b", "gym-a"), false);
  assertEquals(canReuseExistingProfile(null, "gym-a"), false);
});

Deno.test("the relation uses the server-resolved gym", () => {
  assertEquals(
    gymMemberRelation({
      gymId: "gym-a",
      userId: "athlete-a",
      role: "athlete",
      invitedBy: "owner-a",
      joinedAt: "2026-08-25T00:00:00.000Z",
    }),
    {
      gym_id: "gym-a",
      user_id: "athlete-a",
      role: "athlete",
      is_active: true,
      is_coach: false,
      joined_at: "2026-08-25T00:00:00.000Z",
      invited_by: "owner-a",
    },
  );
});

Deno.test("coach capability remains explicit", () => {
  assertEquals(invitedMemberRole("coach"), "coach");
  assertEquals(
    gymMemberRelation({
      gymId: "gym-a",
      userId: "coach-a",
      role: "coach",
      invitedBy: "owner-a",
      joinedAt: "2026-08-25T00:00:00.000Z",
    }).is_coach,
    true,
  );
});

Deno.test("all supported visible roles map to the existing backend contract", () => {
  assertEquals(invitedMemberRole("athlete"), "athlete");
  assertEquals(invitedMemberRole("coach"), "coach");
  assertEquals(invitedMemberRole("admin"), "admin");
  assertEquals(invitedMemberRole("unexpected"), "athlete");
});

Deno.test("a repeated relation remains active without changing its identity", () => {
  const relation = gymMemberRelation({
    gymId: "gym-a",
    userId: "athlete-a",
    role: "admin",
    invitedBy: "owner-a",
    joinedAt: "2026-08-25T00:00:00.000Z",
  });
  assertEquals(relation.gym_id, "gym-a");
  assertEquals(relation.user_id, "athlete-a");
  assertEquals(relation.role, "admin");
  assertEquals(relation.is_active, true);
  assertEquals(relation.is_coach, false);
  assertEquals(relation.joined_at, "2026-08-25T00:00:00.000Z");
});
