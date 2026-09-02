import { assertEquals } from "https://deno.land/std@0.224.0/assert/assert_equals.ts";
import { postScoreReminderCopy } from "./logic.ts";

Deno.test("post-score reminder uses Spanish recipient locale for title and body", () => {
  assertEquals(postScoreReminderCopy("es"), {
    title: "¿Qué tal fue?",
    body: "Comparte tu resultado y cuéntanos qué te pareció el WOD de hoy.",
  });
});

Deno.test("post-score reminder keeps English title and body", () => {
  assertEquals(postScoreReminderCopy("en"), {
    title: "How did it go?",
    body: "Share your score and tell us how today's workout felt.",
  });
});

Deno.test("post-score reminder falls back to English for null and unknown locale", () => {
  for (const locale of [null, "fr"]) {
    assertEquals(postScoreReminderCopy(locale), {
      title: "How did it go?",
      body: "Share your score and tell us how today's workout felt.",
    });
  }
});
