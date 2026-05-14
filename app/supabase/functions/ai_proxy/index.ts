import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
}

const VISION_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct"
const TEXT_MODEL = "llama-3.3-70b-versatile"
const WHISPER_MODEL = "whisper-large-v3-turbo"

function extForMime(mime: string): string {
  const m = mime.toLowerCase().split(";")[0].trim()
  const map: Record<string, string> = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/gif": "gif",
    "video/mp4": "mp4",
    "video/quicktime": "mov",
    "video/webm": "webm",
    "audio/mpeg": "mp3",
    "audio/mp3": "mp3",
    "audio/mp4": "m4a",
    "audio/x-m4a": "m4a",
    "audio/m4a": "m4a",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/webm": "webm",
    "audio/ogg": "ogg",
    "audio/flac": "flac",
    "audio/aac": "aac",
  }
  return map[m] ?? "bin"
}

async function transcribeWithWhisper(
  apiKey: string,
  binary: Uint8Array,
  mediaMimeType: string,
): Promise<string> {
  const blob = new Blob([binary], { type: mediaMimeType })
  const form = new FormData()
  form.append("file", blob, `upload.${extForMime(mediaMimeType)}`)
  form.append("model", WHISPER_MODEL)
  form.append("response_format", "json")

  const tr = await fetch(
    "https://api.groq.com/openai/v1/audio/transcriptions",
    {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    },
  )
  const trData = await tr.json()
  if (!tr.ok) {
    const msg =
      trData.error?.message ?? trData.error ?? JSON.stringify(trData)
    throw new Error(typeof msg === "string" ? msg : JSON.stringify(msg))
  }
  return String(trData.text ?? "").trim() ||
    "(No se detectó habla audible en el archivo.)"
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const body = await req.json()
    const {
      prompt,
      imageBase64,
      history = [],
      mediaBase64,
      mediaMimeType: rawMime,
      mediaKind: rawKind,
      videoPreviewFramesBase64: framesRaw,
    } = body as {
      prompt: string
      imageBase64?: string
      history?: { role: string; content: unknown }[]
      mediaBase64?: string
      mediaMimeType?: string
      mediaKind?: string
      videoPreviewFramesBase64?: unknown
    }

    const apiKey = Deno.env.get("AI_API_KEY")
    const systemPrompt =
      Deno.env.get("SYSTEM_PROMPT") || "Eres la profesora Florencia."

    if (!apiKey) {
      throw new Error("API key not found.")
    }

    const effectiveB64 = (mediaBase64 ?? imageBase64) as string | undefined
    const mediaKind =
      typeof rawKind === "string" ? rawKind.trim().toLowerCase() : ""

    let mediaMimeType = (
      typeof rawMime === "string" && rawMime.trim().length > 0
        ? rawMime.trim()
        : imageBase64
        ? "image/jpeg"
        : ""
    ).toLowerCase()

    if (
      effectiveB64 &&
      effectiveB64.length > 0 &&
      (!mediaMimeType ||
        mediaMimeType === "application/octet-stream" ||
        mediaMimeType === "binary/octet-stream")
    ) {
      if (mediaKind === "video") mediaMimeType = "video/mp4"
      else if (mediaKind === "audio") mediaMimeType = "audio/mpeg"
      else if (mediaKind === "image") mediaMimeType = "image/jpeg"
    }

    if (effectiveB64 && effectiveB64.length > 0 && !mediaMimeType) {
      if (mediaKind === "video") mediaMimeType = "video/mp4"
      else if (mediaKind === "audio") mediaMimeType = "audio/mpeg"
      else mediaMimeType = "image/jpeg"
    }

    const frameB64s: string[] = Array.isArray(framesRaw)
      ? framesRaw
        .filter((x): x is string => typeof x === "string" && x.length > 32)
        .slice(0, 4)
      : []

    const treatsAsVideo =
      mediaKind === "video" ||
      (mediaMimeType.length > 0 && mediaMimeType.startsWith("video/"))

    let content: string | unknown[]
    let model = TEXT_MODEL

    if (effectiveB64 && effectiveB64.length > 0 && mediaMimeType.startsWith("image/")) {
      model = VISION_MODEL
      content = [
        { type: "text", text: prompt },
        {
          type: "image_url",
          image_url: {
            url: `data:${mediaMimeType};base64,${effectiveB64}`,
          },
        },
      ]
    } else if (treatsAsVideo && frameB64s.length > 0) {
      let transcript: string
      if (effectiveB64 && effectiveB64.length > 0) {
        let binary: Uint8Array
        try {
          binary = Uint8Array.from(atob(effectiveB64), (c) =>
            c.charCodeAt(0)
          )
        } catch {
          throw new Error("mediaBase64 inválido (no es base64 válido).")
        }
        transcript = await transcribeWithWhisper(
          apiKey,
          binary,
          mediaMimeType.startsWith("video/") ? mediaMimeType : "video/mp4",
        )
      } else {
        transcript =
          "(El archivo de video no se envió completo por límite de tamaño; " +
          "responde usando solo los fotogramas del mismo clip.)"
      }

      const textPart = [
        "Eres la profesora Florencia.",
        "El usuario envió un VIDEO. Las imágenes de este mensaje son FOTOGRAMAS del mismo clip en distintos instantes.",
        "Transcripción automática del audio (puede tener errores o ser irrelevante):",
        '"""',
        transcript,
        '"""',
        "Responde la petición del usuario priorizando lo que ves en los fotogramas (animales, plantas, ambiente, texto visible).",
        "Usa la transcripción solo como contexto adicional (por ejemplo si alguien nombra la especie en voz alta).",
        "Si no alcanzas a identificar la especie con confianza, dilo y sugiere una toma más cercana o con mejor luz.",
        "",
        "Instrucción del usuario:",
        prompt,
      ].join("\n")

      model = VISION_MODEL
      content = [
        { type: "text", text: textPart },
        ...frameB64s.map((b64) => ({
          type: "image_url",
          image_url: { url: `data:image/jpeg;base64,${b64}` },
        })),
      ]
    } else if (
      effectiveB64 &&
      effectiveB64.length > 0 &&
      (mediaMimeType.startsWith("audio/") || mediaMimeType.startsWith("video/"))
    ) {
      let binary: Uint8Array
      try {
        binary = Uint8Array.from(atob(effectiveB64), (c) =>
          c.charCodeAt(0)
        )
      } catch {
        throw new Error("mediaBase64 inválido (no es base64 válido).")
      }

      const transcript = await transcribeWithWhisper(
        apiKey,
        binary,
        mediaMimeType,
      )
      const kindLabel = mediaMimeType.startsWith("video/") ? "video" : "audio"
      model = TEXT_MODEL
      content = [
        "Eres la profesora Florencia. El usuario envió un archivo de " +
          kindLabel +
          " sin fotogramas visuales.",
        "Su contenido sonoro fue transcrito; el texto entre triple comillas es esa transcripción.",
        "Responde la instrucción del usuario con base en esa transcripción.",
        "Si la transcripción no basta (por ejemplo para identificar una especie solo por imagen), indica que convendría enviar una foto o un video del que se puedan extraer fotogramas.",
        "",
        '"""',
        transcript,
        '"""',
        "",
        "Instrucción del usuario:",
        prompt,
      ].join("\n")
    } else {
      content = prompt
    }

    const groqResponse = await fetch(
      "https://api.groq.com/openai/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model,
          messages: [
            { role: "system", content: systemPrompt },
            ...(history ?? []),
            {
              role: "user",
              content,
            },
          ],
          temperature: 0.5,
        }),
      },
    )

    const data = await groqResponse.json()
    if (!groqResponse.ok) {
      const msg = data.error?.message ?? JSON.stringify(data)
      throw new Error(typeof msg === "string" ? msg : JSON.stringify(msg))
    }

    const reply = data.choices?.[0]?.message?.content
    if (reply == null || String(reply).trim() === "") {
      throw new Error("La IA devolvió una respuesta vacía.")
    }

    return new Response(JSON.stringify({ reply }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : String(error),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
    )
  }
})
