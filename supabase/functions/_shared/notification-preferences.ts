export type NotificationPushPreferences = {
  communications_push_enabled?: boolean | null
  notifications_push_enabled?: boolean | null
} | null

export function shouldSendNotificationPush(
  type: unknown,
  preferences: NotificationPushPreferences,
) {
  if (String(type ?? '') === 'communication') {
    return preferences?.communications_push_enabled !== false
  }
  return preferences?.notifications_push_enabled !== false
}
