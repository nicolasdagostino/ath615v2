import { recipientLanguage } from "../_shared/recipient-locale.ts";

export type ReminderCopy = { title: string; body: string };

export function classReminderCopy(
  locale: unknown,
  classTitle: unknown,
): ReminderCopy {
  const rawTitle = typeof classTitle === "string" ? classTitle.trim() : "";

  if (recipientLanguage(locale) === "es") {
    const title = rawTitle || "Tu clase";
    return {
      title: "Recordatorio de clase",
      body: `${title} empieza en 2 horas. ¡Nos vemos pronto!`,
    };
  }

  const title = rawTitle || "Your class";
  return {
    title: "Class Reminder",
    body: `${title} starts in 2 hours. See you soon!`,
  };
}
