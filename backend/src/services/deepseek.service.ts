export type DeepSeekMessage = {
  role: 'system' | 'user' | 'assistant'
  content: string
}

export async function deepSeekChat(messages: DeepSeekMessage[], opts?: {
  maxTokens?: number
  temperature?: number
}): Promise<{ text: string; model: string }> {
  const apiKey = process.env.DEEPSEEK_API_KEY
  if (!apiKey) {
    throw new Error('AI_DISABLED')
  }

  const base = process.env.DEEPSEEK_API_URL?.replace(/\/$/, '') ?? 'https://api.deepseek.com'
  const model = process.env.DEEPSEEK_MODEL ?? 'deepseek-chat'

  const res = await fetch(`${base}/v1/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      messages,
      max_tokens: opts?.maxTokens ?? 600,
      temperature: opts?.temperature ?? 0.5,
    }),
  })

  if (!res.ok) {
    const t = await res.text()
    throw new Error(`AI_UPSTREAM:${res.status}:${t}`)
  }

  const data = (await res.json()) as any
  const text = data.choices?.[0]?.message?.content ?? ''
  return {
    text: typeof text === 'string' ? text.trim() : '',
    model,
  }
}
