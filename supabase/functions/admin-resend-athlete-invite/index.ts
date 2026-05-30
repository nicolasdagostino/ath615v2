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
    const memberId = String(body.member_id ?? body.memberId ?? '').trim()
    const redirectTo =
      String(body.redirectTo ?? '').trim() || 'athletelab://reset-password'

    if (!memberId) throw new Error('Missing member_id')

    const { data: adminProfile, error: adminError } = await adminClient
      .from('profiles')
      .select('role, gym_id')
      .eq('id', userData.user.id)
      .single()

    if (adminError) throw adminError
    if (adminProfile.role !== 'admin' && adminProfile.role !== 'owner') {
      throw new Error('Only admins can resend invitations')
    }
    if (!adminProfile.gym_id) throw new Error('Admin has no gym_id')

    const { data: memberProfile, error: memberError } = await adminClient
      .from('profiles')
      .select('id, full_name, role, gym_id')
      .eq('id', memberId)
      .single()

    if (memberError) throw memberError
    if (memberProfile.gym_id !== adminProfile.gym_id) {
      throw new Error('Member belongs to another gym')
    }

    const { data: user, error: getUserError } =
      await adminClient.auth.admin.getUserById(memberId)

    if (getUserError || !user.user?.email) {
      throw new Error('Member auth user not found')
    }

    if (user.user.email_confirmed_at || user.user.last_sign_in_at) {
      throw new Error('Member already accepted invitation')
    }

    const { error } = await adminClient.auth.resetPasswordForEmail(user.user.email, {
      redirectTo,
    })

    if (error) throw error

    return new Response(
      JSON.stringify({
        ok: true,
        email: user.user.email,
        sent: true,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e?.message ?? e) }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
