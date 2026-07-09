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
    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')

    if (!stripeSecretKey) {
      throw new Error('Missing STRIPE_SECRET_KEY')
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    const { data: userData, error: userError } =
      await userClient.auth.getUser()

    if (userError || !userData.user) {
      throw new Error('Unauthorized')
    }

    const { data: profile, error: profileError } = await adminClient
      .from('profiles')
      .select('role, gym_id')
      .eq('id', userData.user.id)
      .single()

    if (profileError) throw profileError

    if (profile.role !== 'admin' && profile.role !== 'owner') {
      throw new Error('Only gym admins can refresh Stripe status')
    }

    if (!profile.gym_id) {
      throw new Error('Admin has no gym_id')
    }

    const { data: gym, error: gymError } = await adminClient
      .from('gyms')
      .select('id, stripe_account_id')
      .eq('id', profile.gym_id)
      .single()

    if (gymError) throw gymError

    const stripeAccountId = gym.stripe_account_id?.toString()

    if (!stripeAccountId) {
      throw new Error('Gym has no Stripe account')
    }

    const stripeResponse = await fetch(
      `https://api.stripe.com/v1/accounts/${stripeAccountId}`,
      {
        headers: {
          Authorization: `Bearer ${stripeSecretKey}`,
        },
      },
    )

    const account = await stripeResponse.json()

    if (!stripeResponse.ok) {
      throw new Error(
        account?.error?.message ?? 'Could not retrieve Stripe account',
      )
    }

    const chargesEnabled = account.charges_enabled === true
    const payoutsEnabled = account.payouts_enabled === true
    const detailsSubmitted = account.details_submitted === true

    const { error: updateError } = await adminClient
      .from('gyms')
      .update({
        stripe_onboarding_complete: detailsSubmitted,
        stripe_charges_enabled: chargesEnabled,
        stripe_payouts_enabled: payoutsEnabled,
      })
      .eq('id', gym.id)

    if (updateError) throw updateError

    return new Response(
      JSON.stringify({
        ok: true,
        stripeAccountId,
        onboardingComplete: detailsSubmitted,
        chargesEnabled,
        payoutsEnabled,
      }),
      {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      },
    )
  } catch (e) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: String(e?.message ?? e),
      }),
      {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      },
    )
  }
})
