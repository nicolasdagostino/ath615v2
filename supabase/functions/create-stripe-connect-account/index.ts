import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

async function stripeRequest(
  path: string,
  secretKey: string,
  params: Record<string, string>,
) {
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${secretKey}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(params),
  })

  const json = await response.json()

  if (!response.ok) {
    throw new Error(json?.error?.message ?? `Stripe error on ${path}`)
  }

  return json
}

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
    const refreshUrl = Deno.env.get('STRIPE_CONNECT_REFRESH_URL')
    const returnUrl = Deno.env.get('STRIPE_CONNECT_RETURN_URL')

    if (!stripeSecretKey) throw new Error('Missing STRIPE_SECRET_KEY')
    if (!refreshUrl) throw new Error('Missing STRIPE_CONNECT_REFRESH_URL')
    if (!returnUrl) throw new Error('Missing STRIPE_CONNECT_RETURN_URL')

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    const { data: userData, error: userError } =
      await userClient.auth.getUser()

    if (userError || !userData.user) throw new Error('Unauthorized')

    const { data: profile, error: profileError } = await adminClient
      .from('profiles')
      .select('role, gym_id, email')
      .eq('id', userData.user.id)
      .single()

    if (profileError) throw profileError
    if (profile.role !== 'admin' && profile.role !== 'owner') {
      throw new Error('Only gym admins can connect Stripe')
    }
    if (!profile.gym_id) throw new Error('Admin has no gym_id')

    const { data: gym, error: gymError } = await adminClient
      .from('gyms')
      .select('id, name, email, business_name, stripe_account_id')
      .eq('id', profile.gym_id)
      .single()

    if (gymError) throw gymError

    let stripeAccountId = gym.stripe_account_id as string | null

    if (!stripeAccountId) {
      const account = await stripeRequest('accounts', stripeSecretKey, {
        type: 'express',
        country: 'ES',
        email: String(gym.email ?? profile.email ?? ''),
        'capabilities[card_payments][requested]': 'true',
        'capabilities[transfers][requested]': 'true',
        'business_profile[name]': String(
          gym.business_name ?? gym.name ?? 'ATHLETE615 Gym',
        ),
        'metadata[gym_id]': String(gym.id),
      })

      stripeAccountId = account.id

      const { error: updateError } = await adminClient
        .from('gyms')
        .update({
          stripe_account_id: stripeAccountId,
          stripe_onboarding_complete: false,
          stripe_charges_enabled: false,
          stripe_payouts_enabled: false,
        })
        .eq('id', gym.id)

      if (updateError) throw updateError
    }

    const accountLink = await stripeRequest(
      'account_links',
      stripeSecretKey,
      {
        account: stripeAccountId,
        refresh_url: refreshUrl,
        return_url: returnUrl,
        type: 'account_onboarding',
      },
    )

    return new Response(
      JSON.stringify({
        ok: true,
        url: accountLink.url,
        stripeAccountId,
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
      JSON.stringify({ ok: false, error: String(e?.message ?? e) }),
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
