import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { GoogleAuth } from 'npm:google-auth-library@9'
import { corsHeaders } from '../_shared/cors.ts'

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

    const auth = new GoogleAuth({
      credentials: serviceAccount,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })

    const client = await auth.getClient()
    const accessTokenResponse = await client.getAccessToken()
    const accessToken = accessTokenResponse.token

    if (!accessToken) {
      throw new Error('Missing Google access token')
    }

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

    for (const n of notifications) {
      const { data: tokens, error: tokenError } = await admin
        .from('device_tokens')
        .select('token')
        .eq('user_id', n.user_id)

      if (tokenError) throw tokenError

      for (const t of tokens ?? []) {
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
                token: t.token,
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
          throw new Error(`FCM error: ${await fcmResponse.text()}`)
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
