import { recipientLanguage } from "../_shared/recipient-locale.ts";

export type PostScoreReminderCopy = { title: string; body: string };

export function postScoreReminderCopy(locale: unknown): PostScoreReminderCopy {
  if (recipientLanguage(locale) === "es") {
    return {
      title: "¿Qué tal fue?",
      body: "Comparte tu resultado y cuéntanos qué te pareció el WOD de hoy.",
    };
  }

  return {
    title: "How did it go?",
    body: "Share your score and tell us how today's workout felt.",
  };
}
