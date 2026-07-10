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

    const body = await req.json()
    const planId = String(body.planId ?? '').trim()

    if (!planId) {
      throw new Error('Missing planId')
    }

    const { data: profile, error: profileError } = await adminClient
      .from('profiles')
      .select('id, gym_id, email')
      .eq('id', userData.user.id)
      .single()

    if (profileError) throw profileError
    if (!profile.gym_id) throw new Error('User has no gym')

    const { data: plan, error: planError } = await adminClient
      .from('membership_plans')
      .select('id, gym_id, name, price, currency, is_active')
      .eq('id', planId)
      .eq('gym_id', profile.gym_id)
      .single()

    if (planError) throw planError
    if (plan.is_active !== true) throw new Error('Plan is not active')

    const price = Number(plan.price)

    if (!Number.isFinite(price) || price <= 0) {
      throw new Error('Plan has no valid price')
    }

    const { data: gym, error: gymError } = await adminClient
      .from('gyms')
      .select(
        'id, stripe_account_id, stripe_charges_enabled, stripe_payouts_enabled',
      )
      .eq('id', profile.gym_id)
      .single()

    if (gymError) throw gymError

    const stripeAccountId = gym.stripe_account_id?.toString()

    if (!stripeAccountId) {
      throw new Error('Gym is not connected to Stripe')
    }

    if (
      gym.stripe_charges_enabled !== true ||
      gym.stripe_payouts_enabled !== true
    ) {
      throw new Error('Gym Stripe account is not ready')
    }

    const currency = String(plan.currency ?? 'EUR').toLowerCase()
    const unitAmount = Math.round(price * 100)

    const params = new URLSearchParams()

    params.set('mode', 'payment')
    params.set(
      'expires_at',
      Math.floor(Date.now() / 1000 + 60 * 60).toString(),
    )
    params.set('success_url', 'https://athlete615.com/?checkout=success')
    params.set('cancel_url', 'https://athlete615.com/?checkout=cancel')
    params.set('line_items[0][quantity]', '1')
    params.set('line_items[0][price_data][currency]', currency)
    params.set(
      'line_items[0][price_data][unit_amount]',
      unitAmount.toString(),
    )
    params.set(
      'line_items[0][price_data][product_data][name]',
      String(plan.name),
    )

    params.set('metadata[user_id]', String(profile.id))
    params.set('metadata[gym_id]', String(profile.gym_id))
    params.set('metadata[plan_id]', String(plan.id))

    if (profile.email) {
      params.set('customer_email', String(profile.email))
    }

    const stripeResponse = await fetch(
      'https://api.stripe.com/v1/checkout/sessions',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${stripeSecretKey}`,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Stripe-Account': stripeAccountId,
        },
        body: params,
      },
    )

    const session = await stripeResponse.json()

    if (!stripeResponse.ok) {
      throw new Error(
        session?.error?.message ?? 'Could not create Stripe Checkout Session',
      )
    }

    const checkoutUrl = session.url?.toString()

    if (!checkoutUrl) {
      throw new Error('Missing Stripe Checkout URL')
    }

    const { error: requestError } = await adminClient
      .from('membership_requests')
      .insert({
        user_id: profile.id,
        gym_id: profile.gym_id,
        plan_id: plan.id,
        status: 'pending',
        payment_method: 'card',
        payment_status: 'pending',
        stripe_checkout_session_id: session.id,
        amount_total: session.amount_total,
        currency: session.currency,
      })

    if (requestError) {
      throw requestError
    }

    return new Response(
      JSON.stringify({
        ok: true,
        url: checkoutUrl,
        sessionId: session.id,
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
