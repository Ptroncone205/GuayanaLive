import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { prompt, imageBase64, history = [] } = await req.json()
    const apiKey = Deno.env.get('AI_API_KEY') 
    
    // Retrieve the prompt you just set via the CLI
    const systemPrompt = Deno.env.get('SYSTEM_PROMPT') || "Eres la profesora Florencia.";

    if (!apiKey) {
      throw new Error("API key not found.")
    }

    // Using current 2026 stable models
    const model = imageBase64 
      ? "meta-llama/llama-4-scout-17b-16e-instruct" 
      : "llama-3.3-70b-versatile";
    
    let content: any;
    if (imageBase64) {
      content = [
        { type: "text", text: prompt },
        { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageBase64}` } }
      ];
    } else {
      content = prompt;
    }

    const groqResponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: model,
        messages: [
          { role: "system", content: systemPrompt },
          ...history,
          {
            role: "user",
            content: content,
          },
        ],
        temperature: 0.5,
      }),
    })

    const data = await groqResponse.json()
    const reply = data.choices[0].message.content

    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
    )
  }
})