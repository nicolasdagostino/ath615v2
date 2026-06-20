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

    const { data: adminProfile, error: adminError } = await adminClient
      .from('profiles')
      .select('role, gym_id')
      .eq('id', userData.user.id)
      .single()

    if (adminError) throw adminError
    if (adminProfile.role !== 'admin' && adminProfile.role !== 'owner') {
      throw new Error('Only admins can list members')
    }
    if (!adminProfile.gym_id) throw new Error('Admin has no gym_id')

    const { data: profiles, error: profilesError } = await adminClient
      .from('profiles')
      .select(
        'id, full_name, email, role, gym_id, phone, birth_date, avatar_url, is_active, created_at',
      )
      .eq('gym_id', adminProfile.gym_id)
      .neq('role', 'owner')
      .order('created_at', { ascending: false })

    if (profilesError) throw profilesError

    const userIds = (profiles ?? []).map((profile) => profile.id)

    const { data: memberships, error: membershipsError } = userIds.length
      ? await adminClient
          .from('member_memberships')
          .select(
            'user_id, credits_remaining, expires_at, membership_plans(name, plan_type)',
          )
          .in('user_id', userIds)
          .eq('is_active', true)
          .eq('status', 'active')
          .order('created_at', { ascending: false })
      : { data: [], error: null }

    if (membershipsError) throw membershipsError

    const membershipByUserId = new Map()

    for (const membership of memberships ?? []) {
      const userId = membership.user_id
      if (!membershipByUserId.has(userId)) {
        membershipByUserId.set(userId, membership)
      }
    }

    const members = []

    for (const profile of profiles ?? []) {
      const { data: authUser } = await adminClient.auth.admin.getUserById(profile.id)

      const authEmail = authUser.user?.email ?? null
      const emailConfirmedAt = authUser.user?.email_confirmed_at ?? null
      const lastSignInAt = authUser.user?.last_sign_in_at ?? null
      const membership = membershipByUserId.get(profile.id) ?? null
      const membershipPlan = membership?.membership_plans ?? null

      const invitationStatus = !profile.is_active
        ? 'disabled'
        : emailConfirmedAt || lastSignInAt
        ? 'active'
        : 'pending'

      members.push({
        ...profile,
        email: profile.email ?? authEmail,
        auth_email: authEmail,
        email_confirmed_at: emailConfirmedAt,
        last_sign_in_at: lastSignInAt,
        invitation_status: invitationStatus,
        membership_name: membershipPlan?.name ?? null,
        membership_type: membershipPlan?.plan_type ?? null,
        credits_remaining: membership?.credits_remaining ?? null,
        membership_expires_at: membership?.expires_at ?? null,
      })
    }

    return new Response(JSON.stringify({ ok: true, members }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e?.message ?? e) }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
