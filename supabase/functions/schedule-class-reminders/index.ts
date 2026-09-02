import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { classReminderCopy } from './logic.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(supabaseUrl, serviceRoleKey)

    const now = new Date()
    const windowStart = new Date(now.getTime() + 115 * 60 * 1000)
    const windowEnd = new Date(now.getTime() + 125 * 60 * 1000)

    const { data: classes, error: classesError } = await admin
      .from('classes')
      .select('id, title, starts_at, gym_id')
      .gte('starts_at', windowStart.toISOString())
      .lt('starts_at', windowEnd.toISOString())

    if (classesError) throw classesError

    let createdCount = 0

    for (const klass of classes ?? []) {
      const { data: bookings, error: bookingsError } = await admin
        .from('class_bookings')
        .select('id, user_id, status')
        .eq('class_id', klass.id)
        .eq('status', 'booked')

      if (bookingsError) throw bookingsError

      const userIds = [...new Set((bookings ?? []).map((booking) => booking.user_id))]
      const { data: profiles, error: profilesError } = userIds.length === 0
        ? { data: [], error: null }
        : await admin
          .from('profiles')
          .select('id, preferred_locale')
          .in('id', userIds)

      if (profilesError) throw profilesError
      const localeByUserId = new Map(
        (profiles ?? []).map((profile) => [profile.id, profile.preferred_locale]),
      )

      for (const booking of bookings ?? []) {
        const { data: existing, error: existingError } = await admin
          .from('notifications')
          .select('id')
          .eq('user_id', booking.user_id)
          .eq('type', 'class_reminder')
          .contains('data', {
            source: 'class_reminder',
            classId: klass.id,
          })
          .limit(1)

        if (existingError) throw existingError
        if ((existing ?? []).length > 0) continue

        const copy = classReminderCopy(
          localeByUserId.get(booking.user_id),
          klass.title,
        )
        const { error: insertError } = await admin.from('notifications').insert({
          user_id: booking.user_id,
          title: copy.title,
          body: copy.body,
          type: 'class_reminder',
          data: {
            source: 'class_reminder',
            classId: klass.id,
            bookingId: booking.id,
          },
          scheduled_for: now.toISOString(),
        })

        if (insertError) throw insertError
        createdCount++
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        classes: classes?.length ?? 0,
        createdCount,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
