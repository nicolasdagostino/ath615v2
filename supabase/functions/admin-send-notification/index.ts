import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const allowedAudiences = new Set(['all', 'athlete', 'coach', 'admin'])

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

    const title = String(body.title ?? '').trim()
    const message = String(body.body ?? body.message ?? '').trim()
    const audience = String(body.audience ?? 'all').trim()
    const scheduledForRaw = body.scheduled_for ?? body.scheduledFor ?? null
    const data = body.data && typeof body.data === 'object' ? body.data : {}

    if (!title) throw new Error('Missing title')
    if (!message) throw new Error('Missing body')
    if (!allowedAudiences.has(audience)) throw new Error('Invalid audience')

    const scheduledFor = scheduledForRaw
      ? new Date(String(scheduledForRaw)).toISOString()
      : new Date().toISOString()

    const { data: adminProfile, error: adminError } = await adminClient
      .from('profiles')
      .select('role, gym_id')
      .eq('id', userData.user.id)
      .single()

    if (adminError) throw adminError
    if (adminProfile.role !== 'admin' && adminProfile.role !== 'owner') {
      throw new Error('Only admins can send notifications')
    }
    if (!adminProfile.gym_id) throw new Error('Admin has no gym_id')

    let recipientsQuery = adminClient
      .from('profiles')
      .select('id, role')
      .eq('gym_id', adminProfile.gym_id)
      .eq('is_active', true)
      .neq('role', 'owner')

    if (audience !== 'all') {
      recipientsQuery = recipientsQuery.eq('role', audience)
    }

    const { data: recipients, error: recipientsError } = await recipientsQuery

    if (recipientsError) throw recipientsError

    const rows = (recipients ?? []).map((recipient) => ({
      user_id: recipient.id,
      title,
      body: message,
      type: 'communication',
      data: {
        ...data,
        channel: 'admin',
        audience,
        createdBy: userData.user.id,
      },
      scheduled_for: scheduledFor,
    }))

    if (rows.length === 0) {
      return new Response(JSON.stringify({ ok: true, count: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { error: insertError } = await adminClient
      .from('notifications')
      .insert(rows)

    if (insertError) throw insertError

    return new Response(JSON.stringify({ ok: true, count: rows.length }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e?.message ?? e) }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
