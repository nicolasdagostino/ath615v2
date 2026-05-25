import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) throw new Error('Unauthorized')

    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const userId = userData.user.id

    const deletes = [
      ['device_tokens', 'user_id'],
      ['notifications', 'user_id'],
      ['workout_likes', 'user_id'],
      ['workout_comments', 'user_id'],
      ['class_bookings', 'user_id'],
      ['membership_credit_logs', 'user_id'],
      ['member_memberships', 'user_id'],
      ['personal_records', 'user_id'],
      ['profiles', 'id'],
    ]

    for (const [table, column] of deletes) {
      const { error } = await adminClient.from(table).delete().eq(column, userId)

      if (error) {
        throw new Error(`Could not delete from ${table}: ${error.message}`)
      }
    }

    const { error } = await adminClient.auth.admin.deleteUser(userId)
    if (error) throw new Error(`Could not delete auth user: ${error.message}`)

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e?.message ?? e) }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
