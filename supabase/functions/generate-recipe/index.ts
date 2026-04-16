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
 * Fallback: scrape YouTube watch page HTML for caption tracks.
 * Works from datacenter IPs where innertube ANDROID API may return empty captions.
 */
async function fetchCaptionTracksFromPage(videoId: string): Promise<{
  tracks: CaptionTrack[]
  metadata: VideoMetadata
}> {
  const url = `https://www.youtube.com/watch?v=${videoId}`
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
    },
    signal: AbortSignal.timeout(15_000),
  })

  if (!res.ok) throw new Error(`YouTube page returned ${res.status}`)

  const html = await res.text()

  // Extract ytInitialPlayerResponse from the page
  const match = html.match(/var ytInitialPlayerResponse\s*=\s*(\{.+?\});/)
  if (!match) throw new Error('Could not find player response in page HTML')

  const playerResponse = JSON.parse(match[1])

  const tracks = extractCaptionTracks(playerResponse)
  const metadata = extractMetadata(playerResponse)

  return { tracks, metadata }
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

  return `You are a culinary assistant that extracts recipes from YouTube cooking video transcripts.

IMPORTANT: This IS a cooking video. The title is "${videoTitle}" from channel "${channelName}". Even if the transcript contains casual conversation, introductions, or non-cooking segments, focus on extracting the cooking recipe. Look for ingredient mentions, quantities, cooking instructions, temperatures, and timing throughout the ENTIRE transcript.${langNote}

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
      "quantity": "2 large (approx. 200g)",
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
        {"name": "Onion", "quantity": "2 large (approx. 200g)", "prep_method": "finely chopped"}
      ]
    },
    {
      "step_number": 2,
      "title": "Add oil to pan",
      "description": "Add 2 tablespoons of oil to a heavy-bottomed pan.",
      "timer_seconds": null,
      "flame_level": null,
      "is_prep": true,
      "ingredients": [
        {"name": "Oil", "quantity": "2 tablespoons (30ml)", "prep_method": null}
      ]
    },
    {
      "step_number": 3,
      "title": "Heat oil",
      "description": "Heat the oil on medium flame for 30 seconds until it shimmers.",
      "timer_seconds": 30,
      "flame_level": "medium",
      "is_prep": false,
      "ingredients": []
    }
  ]
}

Rules:
- portion_size: extract from video, default to 2 if not mentioned.
- STEP SPLITTING: Every cooking action MUST be split into TWO separate steps:
  1. An "add/pour/put" step (is_prep: true, no timer, no flame) where ingredients are added to the pan/pot/kadai.
  2. A "cook/heat/fry/boil" step (is_prep: false, with timer_seconds and flame_level) where the actual cooking happens.
- timer_seconds: ONLY for cooking steps involving heat/gas stove. null for prep/add steps.
- flame_level: ONLY "low", "medium", or "high". null for prep/add steps.
- is_prep: true for steps with no cooking (chopping, mixing, adding ingredients to pan). false ONLY for steps where heat/cooking is happening.
- ALTERNATIVE MEASUREMENTS: For every quantity, provide an alternative metric measurement in parentheses where conversion is practical. Examples: "2 tablespoons (30ml)", "1 cup (240ml)", "2 large (approx. 200g)". Skip only when impractical (e.g., "2 basil leaves").
- ingredients: include regional aliases in Hindi, Tamil, Telugu, and Kannada.
- preparations: list things to do before cooking starts (soaking, marinating, etc.). Empty array if none.
- Be precise with quantities. If the video says "some oil", estimate a reasonable amount.
- Order steps exactly as shown in the video.`
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

// ─── OpenAI ─────────────────────────────────────────────────

async function callOpenAI(prompt: string, apiKey: string, model: string): Promise<string> {
  const endpoint = 'https://api.openai.com/v1/chat/completions'

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [{ role: 'user', content: prompt }],
      temperature: 0.1,
      max_tokens: 8192,
      response_format: { type: 'json_object' },
    }),
    signal: AbortSignal.timeout(60_000),
  })

  if (res.status === 429) {
    throw { status: 429, code: 'rate_limited', message: 'Recipe service is busy. Please try again shortly.' }
  }
  if (res.status >= 500) {
    throw { status: 502, code: 'openai_error', message: 'Recipe generation failed. Try again.' }
  }
  if (!res.ok) {
    const body = await res.text()
    throw { status: 502, code: 'openai_error', message: `OpenAI returned ${res.status}: ${body.slice(0, 200)}` }
  }

  const data = await res.json()
  const choices = data.choices ?? []
  if (choices.length === 0) {
    throw { status: 502, code: 'openai_empty', message: 'OpenAI returned no response.' }
  }

  const content = choices[0]?.message?.content
  if (!content) {
    throw { status: 502, code: 'openai_empty', message: 'OpenAI returned empty content.' }
  }

  return content as string
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
    { "name": "Onion", "quantity": "2 large (approx. 200g)", "prep_method": "finely chopped", "aliases": {"hindi": "pyaaz", "tamil": "vengayam", "telugu": "ullipaya", "kannada": "eerulli"} }
  ],
  "preparations": ["Soak rajma overnight in water"],
  "steps": [
    { "step_number": 1, "title": "Chop vegetables", "description": "Finely chop 2 onions.", "timer_seconds": null, "flame_level": null, "is_prep": true, "ingredients": [{"name": "Onion", "quantity": "2 large (approx. 200g)", "prep_method": "finely chopped"}] },
    { "step_number": 2, "title": "Add oil to pan", "description": "Add oil to the pan.", "timer_seconds": null, "flame_level": null, "is_prep": true, "ingredients": [{"name": "Oil", "quantity": "2 tablespoons (30ml)", "prep_method": null}] },
    { "step_number": 3, "title": "Heat oil", "description": "Heat on medium flame for 30 seconds.", "timer_seconds": 30, "flame_level": "medium", "is_prep": false, "ingredients": [] }
  ]
}

Rules: Split every cooking action into TWO steps: (1) add ingredients to pan (is_prep: true, no timer) and (2) cook/heat (is_prep: false, with timer and flame). timer_seconds ONLY for cooking steps. flame_level: "low"/"medium"/"high" or null. For quantities, add alternative metric measurements in parentheses where practical (e.g. "1 cup (240ml)", "2 large (approx. 200g)"). Include ingredient aliases in Hindi, Tamil, Telugu, Kannada. Be precise with quantities. The video may be in any language but return ALL output in English.`

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
  // Accepts two modes:
  //   1. { videoId } — edge function fetches transcript + calls Gemini (full pipeline)
  //   2. { videoId, transcript, transcriptLang, title, author } — client already fetched
  //      transcript, edge function only calls Gemini (keeps API key server-side)
  let videoId: string
  let clientTranscript: string | null = null
  let clientTranscriptLang: string | null = null
  let clientTitle: string | null = null
  let clientAuthor: string | null = null
  try {
    const body = await req.json()
    videoId = body.videoId
    if (body.transcript && typeof body.transcript === 'string') {
      clientTranscript = body.transcript
      clientTranscriptLang = body.transcriptLang ?? 'en'
      clientTitle = body.title ?? ''
      clientAuthor = body.author ?? ''
    }
  } catch {
    return errorResponse('invalid_input', 'Invalid JSON body', 400)
  }

  if (!videoId || typeof videoId !== 'string' || videoId.length < 10) {
    return errorResponse('invalid_input', 'Missing or invalid videoId', 400)
  }

  // Check config — determine LLM provider
  const provider = (Deno.env.get('LLM_PROVIDER') ?? 'gemini').toLowerCase()

  let llmApiKey: string
  let llmModel: string

  if (provider === 'openai') {
    llmApiKey = Deno.env.get('OPENAI_API_KEY') ?? ''
    if (!llmApiKey) {
      return errorResponse('config_error', 'OpenAI API key not configured', 500)
    }
    llmModel = Deno.env.get('OPENAI_MODEL') ?? 'gpt-4o-mini'
  } else {
    llmApiKey = Deno.env.get('GEMINI_API_KEY') ?? ''
    if (!llmApiKey) {
      return errorResponse('config_error', 'Gemini API key not configured', 500)
    }
    llmModel = Deno.env.get('GEMINI_MODEL') ?? 'gemini-2.5-flash-lite'
  }

  let transcript: { text: string; lang: string } | null = null
  let metadata: VideoMetadata = { title: '', author: '', lengthSeconds: '0' }

  // ── Mode A: Client provided transcript — skip YouTube API entirely ──
  if (clientTranscript && clientTranscript.length > 50) {
    console.log(`[generate-recipe] ${videoId}: using client-provided transcript (${clientTranscript.length} chars)`)
    transcript = { text: clientTranscript, lang: clientTranscriptLang! }
    metadata = { title: clientTitle ?? '', author: clientAuthor ?? '', lengthSeconds: '0' }
  } else {
    // ── Mode B: Edge function fetches transcript from YouTube ──
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

    metadata = extractMetadata(playerResponse)

    // Innertube ANDROID client often returns empty metadata — fall back to oEmbed
    if (!metadata.title) {
      try {
        metadata = await fetchOEmbedMetadata(videoId)
      } catch {
        // Non-critical — recipe generation can proceed without metadata
      }
    }

    // ── Step 2: Get transcript ──
    let tracks = extractCaptionTracks(playerResponse)
    console.log(`[generate-recipe] ${videoId}: innertube returned ${tracks.length} caption tracks`)

    // Fallback: if innertube returned no captions (common from datacenter IPs),
    // scrape the YouTube watch page HTML which embeds the player response with captions.
    if (tracks.length === 0) {
      console.log(`[generate-recipe] ${videoId}: trying YouTube page HTML fallback for captions`)
      try {
        const pageData = await fetchCaptionTracksFromPage(videoId)
        tracks = pageData.tracks
        if (!metadata.title && pageData.metadata.title) {
          metadata = pageData.metadata
        }
        console.log(`[generate-recipe] ${videoId}: page fallback returned ${tracks.length} caption tracks`)
      } catch (err) {
        console.error(`[generate-recipe] ${videoId}: page fallback failed:`, err)
      }
    }

    const bestTrack = selectBestTrack(tracks)
    console.log(`[generate-recipe] ${videoId}: best track: ${bestTrack?.languageCode ?? 'none'}`)

    if (bestTrack) {
      try {
        transcript = await fetchTranscript(bestTrack)
        console.log(`[generate-recipe] ${videoId}: transcript ${transcript.text.length} chars, lang=${transcript.lang}`)
      } catch (err) {
        console.error(`[generate-recipe] ${videoId}: transcript fetch failed:`, err)
      }
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
      recipeText = provider === 'openai'
        ? await callOpenAI(prompt, llmApiKey, llmModel)
        : await callGemini(prompt, llmApiKey, llmModel)
    } catch (err: unknown) {
      const e = err as Record<string, unknown>
      if (e.status && e.code) {
        return errorResponse(e.code as string, e.message as string, e.status as number)
      }
      return errorResponse('gemini_error', 'Recipe generation failed.', 502)
    }
  } else {
    // Fallback: try Gemini with video URL (fileData) — Gemini-only capability
    if (provider === 'openai') {
      console.log(`[generate-recipe] ${videoId}: no transcript, OpenAI cannot process video directly`)
      return errorResponse(
        'no_captions',
        'This video has no captions and could not be processed. Try a different video.',
        422,
      )
    }
    console.log(`[generate-recipe] ${videoId}: no transcript, trying fileData fallback`)
    try {
      recipeText = await callGeminiWithVideoUrl(videoId, llmApiKey, llmModel)
    } catch (err) {
      console.error(`[generate-recipe] ${videoId}: fileData fallback failed:`, err)
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
    console.error(`[generate-recipe] ${videoId}: parse failed. Response text (first 500): ${recipeText.slice(0, 500)}`)
    if (e.status && e.code) {
      return errorResponse(e.code as string, e.message as string, e.status as number)
    }
    return errorResponse('parse_error', 'Could not parse recipe from AI response.', 502)
  }

  return jsonResponse({ recipe, metadata })
})
