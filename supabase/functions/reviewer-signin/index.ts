import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const REVIEWER_EMAIL = Deno.env.get('REVIEWER_EMAIL') ?? ''
const REVIEWER_OTP = Deno.env.get('REVIEWER_OTP') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'method_not_allowed' }, 405)
  }

  let email: string
  let otp: string
  try {
    const body = await req.json()
    email = (body.email ?? '').trim().toLowerCase()
    otp = (body.otp ?? '').trim()
  } catch {
    return jsonResponse({ error: 'invalid_body' }, 400)
  }

  // Validate against stored secrets — wrong email or OTP returns the same error
  // to avoid leaking which field was wrong.
  if (
    !REVIEWER_EMAIL ||
    !REVIEWER_OTP ||
    email !== REVIEWER_EMAIL.toLowerCase() ||
    otp !== REVIEWER_OTP
  ) {
    return jsonResponse({ error: 'invalid_credentials' }, 401)
  }

  const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  // Ensure the reviewer account exists and has a confirmed email.
  await supabaseAdmin.auth.admin.createUser({
    email: REVIEWER_EMAIL,
    email_confirm: true,
    user_metadata: { name: 'App Reviewer', food_preference: 'everything' },
  })
  // Ignore error — it just means the user already exists.

  // Generate a one-time magic-link token for this account.
  const { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
    type: 'magiclink',
    email: REVIEWER_EMAIL,
  })

  if (linkError || !linkData?.properties?.hashed_token) {
    return jsonResponse({ error: 'session_generation_failed' }, 500)
  }

  return jsonResponse({ token_hash: linkData.properties.hashed_token })
})
