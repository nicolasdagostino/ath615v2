import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { shouldSendNotificationPush } from './notification-preferences.ts'

Deno.test('missing preferences preserve both push categories', () => {
  assertEquals(shouldSendNotificationPush('communication', null), true)
  assertEquals(shouldSendNotificationPush('class_reminder', null), true)
})

Deno.test('communication preference only controls communications', () => {
  const preferences = {
    communications_push_enabled: false,
    notifications_push_enabled: true,
  }
  assertEquals(shouldSendNotificationPush('communication', preferences), false)
  assertEquals(shouldSendNotificationPush('membership_request', preferences), true)
})

Deno.test('notification preference controls every non-communication type', () => {
  const preferences = {
    communications_push_enabled: true,
    notifications_push_enabled: false,
  }
  assertEquals(shouldSendNotificationPush('communication', preferences), true)
  assertEquals(shouldSendNotificationPush('post_score_reminder', preferences), false)
  assertEquals(shouldSendNotificationPush('unknown', preferences), false)
})

Deno.test('both disabled suppress all FCM delivery', () => {
  const preferences = {
    communications_push_enabled: false,
    notifications_push_enabled: false,
  }
  assertEquals(shouldSendNotificationPush('communication', preferences), false)
  assertEquals(shouldSendNotificationPush('birthday', preferences), false)
})
