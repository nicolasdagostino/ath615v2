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

    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) throw new Error('Unauthorized')

    const body = await req.json()
    const email = String(body.email ?? '').trim().toLowerCase()
    const fullName = String(body.full_name ?? '').trim()
    const gymId = String(body.gym_id ?? '').trim()

    if (!email || !gymId) throw new Error('Missing email or gym_id')

    const { data: profile, error: profileError } = await adminClient
      .from('profiles')
      .select('role, gym_id')
      .eq('id', userData.user.id)
      .single()

    if (profileError) throw profileError
    if (profile.role !== 'owner') throw new Error('Only owners can invite admins')
    if (profile.gym_id !== gymId) throw new Error('Owner can only invite to own gym')

    const { data, error } = await adminClient.auth.admin.inviteUserByEmail(email, {
      data: {
        full_name: fullName || email,
        role: 'admin',
        gym_id: gymId,
      },
      redirectTo: 'athletelab://reset-password',
    })

    if (error) throw error

    return new Response(JSON.stringify({ ok: true, user: data.user }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e?.message ?? e) }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
