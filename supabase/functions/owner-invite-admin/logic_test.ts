import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  gymAcceptsInvitations,
  ownerCanInvite,
  ownerInviteMetadata,
  shouldMaterializeInvitedName,
} from "./logic.ts";

Deno.test("owner invite is scoped to the explicitly selected owned gym", () => {
  assertEquals(
    ownerCanInvite({
      profileRole: "owner",
      gymOwnerId: "u1",
      actorId: "u1",
    }),
    true,
  );
  assertEquals(
    ownerCanInvite({ profileRole: "owner", gymOwnerId: "u2", actorId: "u1" }),
    false,
  );
  assertEquals(
    ownerCanInvite({ profileRole: "admin", gymOwnerId: "u1", actorId: "u1" }),
    false,
  );
  assertEquals(gymAcceptsInvitations("active"), true);
  assertEquals(gymAcceptsInvitations("suspended"), false);
  assertEquals(gymAcceptsInvitations("archived"), false);
});
Deno.test("invite metadata never substitutes email for a missing name", () => {
  assertEquals(ownerInviteMetadata(""), { role: "admin" });
  assertEquals(ownerInviteMetadata(" Felipe "), {
    full_name: "Felipe",
    role: "admin",
  });
});
Deno.test("an existing real name is never overwritten", () => {
  assertEquals(shouldMaterializeInvitedName(null, "Felipe"), true);
  assertEquals(shouldMaterializeInvitedName("Existing", "Felipe"), false);
});
