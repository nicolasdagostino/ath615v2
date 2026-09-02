import { assertEquals } from 'https://deno.land/std@0.224.0/assert/assert_equals.ts'
import { classReminderCopy } from './logic.ts'

Deno.test('class reminder uses Spanish recipient locale for title and body', () => {
  assertEquals(classReminderCopy('es', 'CrossFit'), {
    title: 'Recordatorio de clase',
    body: 'CrossFit empieza en 2 horas. ¡Nos vemos pronto!',
  })
})

Deno.test('class reminder uses English recipient locale for title and body', () => {
  assertEquals(classReminderCopy('en', 'CrossFit'), {
    title: 'Class Reminder',
    body: 'CrossFit starts in 2 hours. See you soon!',
  })
})

Deno.test('class reminder falls back to English for unknown locale', () => {
  assertEquals(classReminderCopy('fr', null), {
    title: 'Class Reminder',
    body: 'Your class starts in 2 hours. See you soon!',
  })
})
