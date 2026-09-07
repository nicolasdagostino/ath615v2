import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { extensionForMime, validImageSignature } from "./logic.ts";

Deno.test("validates supported image signatures", () => {
  assertEquals(
    validImageSignature(
      new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0]),
      "image/png",
    ),
    true,
  );
  assertEquals(
    validImageSignature(new Uint8Array([255, 216, 255, 0]), "image/jpeg"),
    true,
  );
  assertEquals(
    validImageSignature(
      new TextEncoder().encode("RIFF0000WEBP0"),
      "image/webp",
    ),
    true,
  );
  assertEquals(
    validImageSignature(new Uint8Array([1, 2, 3, 4]), "image/png"),
    false,
  );
  assertEquals(extensionForMime("image/webp"), "webp");
});
