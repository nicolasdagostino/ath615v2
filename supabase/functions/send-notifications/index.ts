import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

function base64Url(input: ArrayBuffer | string) {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : new Uint8Array(input)

  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)

  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '')
}

async function getAccessToken(serviceAccount: Record<string, string>) {
  const now = Math.floor(Date.now() / 1000)

  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  const unsignedJwt = `${base64Url(JSON.stringify(header))}.${base64Url(
    JSON.stringify(payload),
  )}`

  const privateKeyPem = serviceAccount.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '')

  const privateKeyDer = Uint8Array.from(atob(privateKeyPem), (c) =>
    c.charCodeAt(0),
  )

  const key = await crypto.subtle.importKey(
    'pkcs8',
    privateKeyDer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsignedJwt),
  )

  const jwt = `${unsignedJwt}.${base64Url(signature)}`

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const tokenJson = await tokenResponse.json()

  if (!tokenResponse.ok) {
    throw new Error(`Google OAuth error: ${JSON.stringify(tokenJson)}`)
  }

  if (!tokenJson.access_token) {
    throw new Error('Missing Google OAuth access token')
  }

  return tokenJson.access_token as string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')

    if (!serviceAccountRaw) {
      throw new Error('Missing FIREBASE_SERVICE_ACCOUNT_JSON')
    }

    const serviceAccount = JSON.parse(serviceAccountRaw)
    const accessToken = await getAccessToken(serviceAccount)
    const admin = createClient(supabaseUrl, serviceRoleKey)

    const { data: notifications, error } = await admin
      .from('notifications')
      .select('*')
      .lte('scheduled_for', new Date().toISOString())
      .is('sent_at', null)
      .limit(50)

    if (error) throw error

    if (!notifications || notifications.length === 0) {
      return new Response(JSON.stringify({ ok: true, count: 0, sentCount: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    let sentCount = 0
    const sentTokens = new Set<string>()

    for (const n of notifications) {
      const { data: tokens, error: tokenError } = await admin
        .from('device_tokens')
        .select('token')
        .eq('user_id', n.user_id)

      if (tokenError) throw tokenError

      const uniqueTokens = [...new Set((tokens ?? []).map((t) => t.token).filter(Boolean))]

      for (const token of uniqueTokens) {
        if (sentTokens.has(token)) continue
        sentTokens.add(token)

        const fcmResponse = await fetch(
          `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              message: {
                token,
                notification: {
                  title: n.title,
                  body: n.body,
                },
                data: {
                  type: String(n.type ?? ''),
                  workoutId: String(n.data?.workoutId ?? ''),
                  notificationId: String(n.id),
                },
                apns: {
                  payload: {
                    aps: {
                      sound: 'default',
                    },
                  },
                },
              },
            }),
          },
        )

        if (!fcmResponse.ok) {
          const errorText = await fcmResponse.text()
          console.error(
            `FCM send failed notification=${n.id} user=${n.user_id} token=${String(token).slice(0, 18)}... error=${errorText}`,
          )
          continue
        }

        sentCount++
      }
    }

    const ids = notifications.map((n) => n.id)

    await admin
      .from('notifications')
      .update({ sent_at: new Date().toISOString() })
      .in('id', ids)

    return new Response(
      JSON.stringify({ ok: true, count: notifications.length, sentCount }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
