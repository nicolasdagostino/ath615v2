import { assertThrows } from "https://deno.land/std@0.224.0/assert/assert_throws.ts";
import {
  assertEffectiveGymSelection,
  assertGymOperational,
} from "./gym_lifecycle.ts";

Deno.test("only active gyms permit operational Edge Function work", () => {
  assertGymOperational("active");
  assertThrows(() => assertGymOperational("suspended"), Error, "not active");
  assertThrows(() => assertGymOperational("archived"), Error, "not active");
  assertThrows(() => assertGymOperational(null), Error, "not active");
});

Deno.test("legacy service-role functions require the authenticated effective gym", () => {
  assertEffectiveGymSelection("gym-a", "gym-a");
  assertThrows(
    () => assertEffectiveGymSelection("gym-a", null),
    Error,
    "no active effective gym",
  );
  assertThrows(
    () => assertEffectiveGymSelection("gym-a", "gym-b"),
    Error,
    "no active effective gym",
  );
});
