import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { postScoreReminderCopy } from './logic.ts'

function workoutDateFromStartsAt(raw: string) {
  return raw.split('T')[0]
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(supabaseUrl, serviceRoleKey)

    const now = new Date()
    const windowStart = new Date(now.getTime() - 25 * 60 * 1000)
    const windowEnd = new Date(now.getTime() - 15 * 60 * 1000)

    const { data: classes, error: classesError } = await admin
      .from('classes')
      .select('id, title, starts_at, duration_minutes, gym_id, program_id')
      .not('program_id', 'is', null)
      .lte('starts_at', now.toISOString())

    if (classesError) throw classesError

    let createdCount = 0
    let matchedClasses = 0

    for (const klass of classes ?? []) {
      const startsAt = new Date(klass.starts_at)
      const durationMinutes = Number(klass.duration_minutes ?? 60)
      const finishedAt = new Date(startsAt.getTime() + durationMinutes * 60 * 1000)
      const reminderAt = new Date(finishedAt.getTime() + 20 * 60 * 1000)

      if (reminderAt < windowStart || reminderAt >= windowEnd) continue

      matchedClasses++

      const workoutDate = workoutDateFromStartsAt(String(klass.starts_at))

      const { data: workout, error: workoutError } = await admin
        .from('workouts')
        .select('id')
        .eq('gym_id', klass.gym_id)
        .eq('program_id', klass.program_id)
        .eq('workout_date', workoutDate)
        .maybeSingle()

      if (workoutError) throw workoutError
      if (!workout?.id) continue

      const { data: bookings, error: bookingsError } = await admin
        .from('class_bookings')
        .select('id, user_id, status')
        .eq('class_id', klass.id)
        .in('status', ['booked', 'attended'])

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
          .eq('type', 'post_score_reminder')
          .contains('data', {
            source: 'post_score_reminder',
            classId: klass.id,
            workoutId: workout.id,
          })
          .limit(1)

        if (existingError) throw existingError
        if ((existing ?? []).length > 0) continue

        const copy = postScoreReminderCopy(localeByUserId.get(booking.user_id))
        const { error: insertError } = await admin.from('notifications').insert({
          user_id: booking.user_id,
          title: copy.title,
          body: copy.body,
          type: 'post_score_reminder',
          data: {
            source: 'post_score_reminder',
            classId: klass.id,
            bookingId: booking.id,
            workoutId: workout.id,
            workoutDate,
            action: 'post_score',
          },
          scheduled_for: now.toISOString(),
        })

        if (insertError) throw insertError
        createdCount++
      }
    }

    return new Response(
      JSON.stringify({ ok: true, matchedClasses, createdCount }),
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
