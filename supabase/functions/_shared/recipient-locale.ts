export type RecipientLanguage = "en" | "es";

export function recipientLanguage(locale: unknown): RecipientLanguage {
  if (typeof locale !== "string") return "en";
  return locale.trim().toLowerCase().split(/[-_]/)[0] === "es" ? "es" : "en";
}
