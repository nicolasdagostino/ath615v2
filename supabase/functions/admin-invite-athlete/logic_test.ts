import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  canInviteAthlete,
  canReuseExistingProfile,
  cleanupFailedInvite,
  gymMemberRelation,
  invitedMemberRole,
  invitedProfilePatch,
  publicInviteError,
} from "./logic.ts";

Deno.test("only an effective owner or admin can invite", () => {
  assertEquals(canInviteAthlete("owner"), true);
  assertEquals(canInviteAthlete("admin"), true);
  assertEquals(canInviteAthlete("coach"), false);
  assertEquals(canInviteAthlete("athlete"), false);
});

Deno.test("limit errors are stable and unknown backend errors are hidden", () => {
  assertEquals(publicInviteError(new Error("gym_member_limit_reached")), {
    code: "gym_member_limit_reached",
    error: "gym_member_limit_reached",
    status: 409,
  });
  assertEquals(
    publicInviteError(new Error("P0001 function secret_rpc failed")),
    {
      code: null,
      error: "request_failed",
      status: 400,
    },
  );
});

Deno.test("Auth failure releases reservation without deleting an existing identity", async () => {
  const calls: string[] = [];
  await cleanupFailedInvite({
    createdAuthUserId: null,
    reservationId: "reservation-a",
    deleteCreatedUser: (id) => Promise.resolve(calls.push(`delete:${id}`)),
    releaseReservation: (id) => Promise.resolve(calls.push(`release:${id}`)),
  });
  assertEquals(calls, ["release:reservation-a"]);
});

Deno.test("materialization failure cleans only the identity created by this request", async () => {
  const calls: string[] = [];
  await cleanupFailedInvite({
    createdAuthUserId: "new-user",
    reservationId: "reservation-a",
    deleteCreatedUser: (id) => Promise.resolve(calls.push(`delete:${id}`)),
    releaseReservation: (id) => Promise.resolve(calls.push(`release:${id}`)),
  });
  assertEquals(calls, ["delete:new-user", "release:reservation-a"]);
});

Deno.test("reservation precedes Auth and successful materialization consumes it", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertEquals(
    source.indexOf('"reserve_effective_gym_athlete_slot"') <
      source.indexOf("inviteUserByEmail"),
    true,
  );
  assertEquals(
    source.indexOf('"materialize_reserved_gym_athlete"') >
      source.indexOf("inviteUserByEmail"),
    true,
  );
  assertEquals(source.includes("reservationId = null"), true);
});

Deno.test("an existing profile can receive a relationship in another effective gym", () => {
  assertEquals(canReuseExistingProfile("user-a"), true);
  assertEquals(canReuseExistingProfile(null), false);
});

Deno.test("invited name only fills a missing profile name", () => {
  assertEquals(
    invitedProfilePatch({
      existingFullName: null,
      invitedFullName: "Felipe D'Agostino",
      phone: "",
      birthDate: "",
    }),
    { full_name: "Felipe D'Agostino" },
  );
  assertEquals(
    invitedProfilePatch({
      existingFullName: "Existing Name",
      invitedFullName: "Replacement",
      phone: "",
      birthDate: "",
    }),
    {},
  );
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
