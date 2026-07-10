import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

async function hmacSha256(secret: string, payload: string) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(payload),
  )

  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

async function verifyStripeSignature(
  body: string,
  signatureHeader: string | null,
  webhookSecret: string,
) {
  if (!signatureHeader) return false

  const parts = Object.fromEntries(
    signatureHeader.split(',').map((part) => {
      const [key, value] = part.split('=')
      return [key, value]
    }),
  )

  const timestamp = parts.t
  const signature = parts.v1

  if (!timestamp || !signature) return false

  const expected = await hmacSha256(webhookSecret, `${timestamp}.${body}`)

  return expected === signature
}

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')

    if (!webhookSecret) {
      throw new Error('Missing STRIPE_WEBHOOK_SECRET')
    }

    const body = await req.text()
    const signature = req.headers.get('stripe-signature')
    const isValid = await verifyStripeSignature(
      body,
      signature,
      webhookSecret,
    )

    if (!isValid) {
      return new Response('Invalid signature', { status: 400 })
    }

    const event = JSON.parse(body)

    const session = event.data?.object
    const stripeAccountId = event.account?.toString()

    if (!session?.id) {
      throw new Error('Missing checkout session')
    }

    if (!stripeAccountId) {
      throw new Error('Missing connected Stripe account')
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    if (event.type === 'checkout.session.completed') {
      if (session.payment_status !== 'paid') {
        throw new Error('Checkout Session payment is not paid')
      }

      const { error } = await adminClient.rpc(
        'complete_card_membership_request',
        {
          p_checkout_session_id: session.id,
          p_payment_intent_id: session.payment_intent ?? null,
          p_amount_total: session.amount_total ?? null,
          p_currency: session.currency ?? null,
          p_stripe_account_id: stripeAccountId,
        },
      )

      if (error) throw error
    } else if (event.type === 'checkout.session.expired') {
      const { error } = await adminClient.rpc(
        'cancel_expired_card_membership_request',
        {
          p_checkout_session_id: session.id,
          p_stripe_account_id: stripeAccountId,
        },
      )

      if (error) throw error
    } else {
      return new Response(JSON.stringify({ ok: true, ignored: true }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: String(e?.message ?? e),
      }),
      {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      },
    )
  }
})
