import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ownerCanInvite,
  ownerInviteMetadata,
  shouldMaterializeInvitedName,
} from "./logic.ts";

Deno.test("owner invite is scoped to the owned effective gym", () => {
  assertEquals(
    ownerCanInvite({ profileRole: "owner", gymOwnerId: "u1", actorId: "u1" }),
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
