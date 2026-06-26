import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(supabaseUrl, serviceRoleKey)

    const now = new Date()
    const month = now.getUTCMonth() + 1
    const day = now.getUTCDate()
    const year = now.getUTCFullYear()

    const { data: profiles, error: profilesError } = await admin
      .from('profiles')
      .select('id, full_name, birth_date, is_active, role')
      .eq('is_active', true)
      .neq('role', 'owner')
      .not('birth_date', 'is', null)

    if (profilesError) throw profilesError

    let createdCount = 0

    for (const profile of profiles ?? []) {
      const birthDate = new Date(profile.birth_date)
      if (birthDate.getUTCMonth() + 1 !== month) continue
      if (birthDate.getUTCDate() !== day) continue

      const { data: existing, error: existingError } = await admin
        .from('notifications')
        .select('id')
        .eq('user_id', profile.id)
        .eq('type', 'birthday')
        .contains('data', {
          source: 'birthday',
          year,
        })
        .limit(1)

      if (existingError) throw existingError
      if ((existing ?? []).length > 0) continue

      const name = profile.full_name?.toString().trim()
      const title = 'Happy Birthday!'
      const body = name
        ? `Happy birthday, ${name}! Have an amazing day.`
        : 'Happy birthday! Have an amazing day.'

      const { error: insertError } = await admin.from('notifications').insert({
        user_id: profile.id,
        title,
        body,
        type: 'birthday',
        data: {
          source: 'birthday',
          year,
        },
        scheduled_for: now.toISOString(),
      })

      if (insertError) throw insertError
      createdCount++
    }

    return new Response(
      JSON.stringify({ ok: true, checked: profiles?.length ?? 0, createdCount }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e?.message ?? e) }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
