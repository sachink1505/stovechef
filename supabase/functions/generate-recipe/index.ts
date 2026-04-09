import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const INNERTUBE_URL = 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false'
const ANDROID_USER_AGENT = 'com.google.android.youtube/20.10.38 (Linux; U; Android 14)'
const ANDROID_CLIENT = { clientName: 'ANDROID', clientVersion: '20.10.38' }

// ─── Helpers ────────────────────────────────────────────────

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function errorResponse(error: string, message: string, status: number) {
  return jsonResponse({ error, message }, status)
}

// ─── YouTube: Innertube ANDROID API ─────────────────────────

interface CaptionTrack {
  baseUrl: string
  languageCode: string
  kind?: string
  name?: { simpleText?: string }
}

interface VideoMetadata {
  title: string
  author: string
  lengthSeconds: string
}

async function fetchPlayerResponse(videoId: string) {
  const res = await fetch(INNERTUBE_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': ANDROID_USER_AGENT,
    },
    body: JSON.stringify({
      videoId,
      context: { client: ANDROID_CLIENT },
    }),
    signal: AbortSignal.timeout(15_000),
  })

  if (!res.ok) {
    throw new Error(`Innertube API returned ${res.status}`)
  }

  return await res.json()
}

function extractMetadata(playerResponse: Record<string, unknown>): VideoMetadata {
  const details = (playerResponse.videoDetails ?? {}) as Record<string, unknown>
  return {
    title: (details.title as string) ?? '',
    author: (details.author as string) ?? '',
    lengthSeconds: (details.lengthSeconds as string) ?? '0',
  }
}

/** Fetch metadata via YouTube oEmbed API (public, reliable fallback). */
async function fetchOEmbedMetadata(videoId: string): Promise<VideoMetadata> {
  const url = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${videoId}&format=json`
  const res = await fetch(url, { signal: AbortSignal.timeout(10_000) })
  if (!res.ok) throw new Error(`oEmbed returned ${res.status}`)
  const data = await res.json()
  return {
    title: (data.title as string) ?? '',
    author: (data.author_name as string) ?? '',
    lengthSeconds: '0',
  }
}

function extractCaptionTracks(playerResponse: Record<string, unknown>): CaptionTrack[] {
  const captions = (playerResponse.captions ?? {}) as Record<string, unknown>
  const renderer = (captions.playerCaptionsTracklistRenderer ?? {}) as Record<string, unknown>
  return (renderer.captionTracks ?? []) as CaptionTrack[]
}

/**
 * Select the best caption track.
 * Priority: manual English > auto English > any manual > any auto.
 */
function selectBestTrack(tracks: CaptionTrack[]): CaptionTrack | null {
  if (tracks.length === 0) return null

  let best: CaptionTrack | null = null
  let bestScore = -1

  for (const track of tracks) {
    const lang = (track.languageCode ?? '').toLowerCase()
    const isEnglish = lang.startsWith('en')
    const isAuto = track.kind === 'asr'

    let score: number
    if (isEnglish && !isAuto) score = 4
    else if (isEnglish && isAuto) score = 3
    else if (!isEnglish && !isAuto) score = 2
    else score = 1

    if (score > bestScore) {
      bestScore = score
      best = track
    }
  }

  return best
}

async function fetchTranscript(track: CaptionTrack): Promise<{ text: string; lang: string }> {
  // Append json3 format
  const url = track.baseUrl.includes('&fmt=')
    ? track.baseUrl.replace(/&fmt=[^&]*/, '&fmt=json3')
    : track.baseUrl + '&fmt=json3'

  const res = await fetch(url, {
    headers: { 'User-Agent': ANDROID_USER_AGENT },
    signal: AbortSignal.timeout(15_000),
  })

  if (!res.ok || res.status !== 200) {
    throw new Error(`Caption fetch returned ${res.status}`)
  }

  const body = await res.text()
  if (!body || body.length === 0) {
    throw new Error('Caption response is empty')
  }

  let text: string

  if (body.trimStart().startsWith('{')) {
    // JSON format (json3)
    const data = JSON.parse(body)
    const events = (data.events ?? []) as Array<Record<string, unknown>>
    const parts: string[] = []
    for (const event of events) {
      const segs = (event.segs ?? []) as Array<Record<string, unknown>>
      for (const seg of segs) {
        const utf8 = (seg.utf8 as string) ?? ''
        parts.push(utf8 === '\n' ? ' ' : utf8)
      }
    }
    text = parts.join('')
  } else {
    // XML timedtext format (YouTube sometimes returns XML even for fmt=json3).
    // Extract text from <s> tags: <s t="..." ac="...">word</s>
    const sTagPattern = /<s[^>]*>([^<]*)<\/s>/g
    const matches: string[] = []
    let match: RegExpExecArray | null
    while ((match = sTagPattern.exec(body)) !== null) {
      const word = match[1].trim()
      if (word) matches.push(word)
    }

    if (matches.length > 0) {
      text = matches.join(' ')
    } else {
      // Fallback: extract from <text> tags (srv1 format)
      const textTagPattern = /<text[^>]*>([\s\S]*?)<\/text>/g
      const textMatches: string[] = []
      while ((match = textTagPattern.exec(body)) !== null) {
        const seg = match[1].replace(/<[^>]+>/g, '').replace(/&amp;/g, '&')
          .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'").replace(/&apos;/g, "'").trim()
        if (seg) textMatches.push(seg)
      }
      text = textMatches.join(' ')
    }
  }

  text = text.trim()
  if (!text) {
    throw new Error('Transcript text is empty after parsing')
  }

  // Cap transcript length to keep Gemini response time under the edge function timeout.
  // 8000 chars covers all recipe content; Hindi/non-Latin scripts use more chars per word
  // so we allow a higher limit for non-ASCII text.
  const isNonLatin = /[^\u0000-\u024F]/.test(text.slice(0, 100))
  const MAX_TRANSCRIPT_CHARS = isNonLatin ? 12000 : 8000
  if (text.length > MAX_TRANSCRIPT_CHARS) {
    text = text.slice(0, MAX_TRANSCRIPT_CHARS)
  }

  return { text, lang: track.languageCode ?? 'en' }
}

// ─── Gemini ─────────────────────────────────────────────────

function buildRecipePrompt(
  transcript: string,
  videoTitle: string,
  channelName: string,
  transcriptLang: string,
): string {
  const langNote = transcriptLang.startsWith('en')
    ? ''
    : `\n\nIMPORTANT: The transcript is in language code "${transcriptLang}" (not English). ` +
      'Understand the transcript in its original language but return ALL recipe output (title, ' +
      'descriptions, ingredient names, step instructions) in English.\n'

  return `You are a culinary assistant. Given a transcript from a YouTube cooking video, extract a precise, structured recipe in JSON format.

Video title: ${videoTitle}
Channel: ${channelName}${langNote}

Transcript:
${transcript}

Return ONLY valid JSON (no markdown, no backticks) with this exact structure:
{
  "title": "Recipe name",
  "cooking_time_minutes": 30,
  "portion_size": 2,
  "ingredients": [
    {
      "name": "Onion",
      "quantity": "2 large or 200 grams",
      "prep_method": "finely chopped",
      "aliases": {"hindi": "pyaaz", "tamil": "vengayam", "telugu": "ullipaya", "kannada": "eerulli"}
    }
  ],
  "preparations": [
    "Soak rajma overnight in water",
    "Wash and drain the rajma"
  ],
  "steps": [
    {
      "step_number": 1,
      "title": "Chop vegetables",
      "description": "Finely chop 2 onions, mince 4 cloves of garlic, and dice 2 tomatoes.",
      "timer_seconds": null,
      "flame_level": null,
      "is_prep": true,
      "ingredients": [
        {"name": "Onion", "quantity": "2 large", "prep_method": "finely chopped"}
      ]
    },
    {
      "step_number": 2,
      "title": "Heat oil",
      "description": "Add 2 tablespoons of oil to a heavy-bottomed pan and heat on medium flame for 30 seconds.",
      "timer_seconds": 30,
      "flame_level": "medium",
      "is_prep": false,
      "ingredients": [
        {"name": "Oil", "quantity": "2 tablespoons", "prep_method": null}
      ]
    }
  ]
}

Rules:
- portion_size: extract from video, default to 2 if not mentioned.
- timer_seconds: ONLY for steps involving heat/gas stove. null for prep steps. Infer timing from context if not explicitly stated.
- flame_level: ONLY "low", "medium", or "high". null for prep steps.
- is_prep: true for steps with no cooking (chopping, mixing dry ingredients, soaking). false for anything on the stove.
- ingredients: include regional aliases in Hindi, Tamil, Telugu, and Kannada.
- preparations: list things to do before cooking starts (soaking, marinating, etc.). Empty array if none.
- Be precise with quantities. If the video says "some oil", estimate a reasonable amount.
- Order steps exactly as shown in the video.
- Separate prep and cooking into distinct steps.`
}

async function callGemini(prompt: string, apiKey: string, model: string): Promise<string> {
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 8192,
        responseMimeType: 'application/json',
      },
    }),
    signal: AbortSignal.timeout(60_000),
  })

  if (res.status === 429) {
    throw { status: 429, code: 'rate_limited', message: 'Recipe service is busy. Please try again shortly.' }
  }
  if (res.status >= 500) {
    throw { status: 502, code: 'gemini_error', message: 'Recipe generation failed. Try again.' }
  }
  if (!res.ok) {
    const body = await res.text()
    throw { status: 502, code: 'gemini_error', message: `Gemini returned ${res.status}: ${body.slice(0, 200)}` }
  }

  const data = await res.json()
  const candidates = data.candidates ?? []
  if (candidates.length === 0) {
    throw { status: 502, code: 'gemini_empty', message: 'Gemini returned no response.' }
  }

  const parts = candidates[0]?.content?.parts ?? []
  if (parts.length === 0) {
    throw { status: 502, code: 'gemini_empty', message: 'Gemini returned empty content.' }
  }

  return parts[0].text as string
}

function extractRecipeJson(responseText: string): Record<string, unknown> {
  let text = responseText.trim()

  // Find the first { and last } — extract the JSON object regardless of surrounding text/fences
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start !== -1 && end > start) {
    text = text.slice(start, end + 1)
  }

  try {
    return JSON.parse(text)
  } catch {
    throw { status: 502, code: 'parse_error', message: 'Could not parse recipe from AI response.' }
  }
}

// ─── Gemini fileData fallback (for captionless videos) ──────

async function callGeminiWithVideoUrl(
  videoId: string,
  apiKey: string,
  model: string,
): Promise<string> {
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`
  const videoUrl = `https://www.youtube.com/watch?v=${videoId}`

  const prompt = `You are a culinary assistant. Watch this cooking video and extract a precise, structured recipe in JSON format.

Return ONLY valid JSON (no markdown, no backticks) with this exact structure:
{
  "title": "Recipe name",
  "cooking_time_minutes": 30,
  "portion_size": 2,
  "ingredients": [
    { "name": "Onion", "quantity": "2 large or 200 grams", "prep_method": "finely chopped", "aliases": {"hindi": "pyaaz", "tamil": "vengayam", "telugu": "ullipaya", "kannada": "eerulli"} }
  ],
  "preparations": ["Soak rajma overnight in water"],
  "steps": [
    { "step_number": 1, "title": "Chop vegetables", "description": "Finely chop 2 onions.", "timer_seconds": null, "flame_level": null, "is_prep": true, "ingredients": [{"name": "Onion", "quantity": "2 large", "prep_method": "finely chopped"}] }
  ]
}

Rules: timer_seconds ONLY for stove steps (null for prep). flame_level: "low"/"medium"/"high" or null. is_prep: true for non-cooking steps. Include ingredient aliases in Hindi, Tamil, Telugu, Kannada. Be precise with quantities. The video may be in any language but return ALL output in English.`

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    },
    body: JSON.stringify({
      contents: [{
        parts: [
          { fileData: { fileUri: videoUrl, mimeType: 'video/*' } },
          { text: prompt },
        ],
      }],
      generationConfig: { temperature: 0.1, maxOutputTokens: 8192 },
    }),
    signal: AbortSignal.timeout(120_000),
  })

  if (!res.ok) {
    throw new Error(`Gemini video processing returned ${res.status}`)
  }

  const data = await res.json()
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text
  if (!text) {
    throw new Error('Gemini returned no content for video')
  }

  return text as string
}

// ─── Main handler ───────────────────────────────────────────

serve(async (req) => {
  if (req.method !== 'POST') {
    return errorResponse('method_not_allowed', 'Only POST is accepted', 405)
  }

  // Verify auth
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return errorResponse('unauthorized', 'Missing Authorization header', 401)
  }

  // Parse request
  let videoId: string
  try {
    const body = await req.json()
    videoId = body.videoId
  } catch {
    return errorResponse('invalid_input', 'Invalid JSON body', 400)
  }

  if (!videoId || typeof videoId !== 'string' || videoId.length < 10) {
    return errorResponse('invalid_input', 'Missing or invalid videoId', 400)
  }

  // Check config
  const apiKey = Deno.env.get('GEMINI_API_KEY')
  if (!apiKey) {
    return errorResponse('config_error', 'Gemini API key not configured', 500)
  }
  const model = Deno.env.get('GEMINI_MODEL') ?? 'gemini-2.5-flash-lite'

  // ── Step 1: Fetch player response from YouTube ──
  let playerResponse: Record<string, unknown>
  try {
    playerResponse = await fetchPlayerResponse(videoId)
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'Unknown error'
    return errorResponse('youtube_error', `Failed to fetch video info: ${msg}`, 502)
  }

  // Check if video is playable
  const playabilityStatus = (playerResponse.playabilityStatus as Record<string, unknown>) ?? {}
  if (playabilityStatus.status === 'ERROR' || playabilityStatus.status === 'UNPLAYABLE') {
    const reason = (playabilityStatus.reason as string) ?? 'This video is unavailable or private.'
    return errorResponse('video_unavailable', reason, 422)
  }

  let metadata = extractMetadata(playerResponse)

  // Innertube ANDROID client often returns empty metadata — fall back to oEmbed
  if (!metadata.title) {
    try {
      metadata = await fetchOEmbedMetadata(videoId)
    } catch {
      // Non-critical — recipe generation can proceed without metadata
    }
  }

  // ── Step 2: Get transcript ──
  const tracks = extractCaptionTracks(playerResponse)
  const bestTrack = selectBestTrack(tracks)

  let transcript: { text: string; lang: string } | null = null

  if (bestTrack) {
    try {
      transcript = await fetchTranscript(bestTrack)
    } catch {
      // Caption URL returned empty — fall through to video fallback
    }
  }

  // ── Step 3: Generate recipe ──
  let recipeText: string

  if (transcript && transcript.text.length > 50) {
    // Primary path: transcript → Gemini text prompt
    const prompt = buildRecipePrompt(
      transcript.text,
      metadata.title,
      metadata.author,
      transcript.lang,
    )

    try {
      recipeText = await callGemini(prompt, apiKey, model)
    } catch (err: unknown) {
      const e = err as Record<string, unknown>
      if (e.status && e.code) {
        return errorResponse(e.code as string, e.message as string, e.status as number)
      }
      return errorResponse('gemini_error', 'Recipe generation failed.', 502)
    }
  } else {
    // Fallback: try Gemini with video URL (fileData)
    try {
      recipeText = await callGeminiWithVideoUrl(videoId, apiKey, model)
    } catch {
      return errorResponse(
        'no_captions',
        'This video has no captions and could not be processed. Try a different video.',
        422,
      )
    }
  }

  // ── Step 4: Parse and return ──
  let recipe: Record<string, unknown>
  try {
    recipe = extractRecipeJson(recipeText)
  } catch (err: unknown) {
    const e = err as Record<string, unknown>
    if (e.status && e.code) {
      return errorResponse(e.code as string, e.message as string, e.status as number)
    }
    return errorResponse('parse_error', 'Could not parse recipe.', 502)
  }

  return jsonResponse({ recipe, metadata })
})
