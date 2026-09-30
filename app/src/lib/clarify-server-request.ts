import type { ServerRequest } from '@hermes/shared'

import { setClarifyRequest } from '@/store/clarify'
import { rememberServerRequest } from '@/store/server-requests'

/** Batch clarify qids keyed by server request id (hermesweb single-card fallback). */
const batchQids = new Map<string, string[]>()

export function getClarifyBatchQids(requestId: string): string[] | undefined {
  return batchQids.get(requestId)
}

export function clearClarifyBatchQids(requestId: string): void {
  batchQids.delete(requestId)
}

type ParsedQuestion = {
  qid: string
  question: string
  choices: string[] | null
}

function parseWireQuestions(rawQuestions: unknown[]): ParsedQuestion[] {
  const parsed: ParsedQuestion[] = []

  for (const [index, item] of rawQuestions.entries()) {
    if (!item || typeof item !== 'object') {
      continue
    }

    const row = item as Record<string, unknown>
    const qid = typeof row.qid === 'string' ? row.qid : `q${index}`
    const question = typeof row.question === 'string' ? row.question.trim() : ''

    if (!question) {
      continue
    }

    const rawChoices = row.choices
    const choices = Array.isArray(rawChoices)
      ? rawChoices.filter((c): c is string => typeof c === 'string' && c.trim().length > 0)
      : null

    parsed.push({
      choices: choices && choices.length > 0 ? choices : null,
      qid,
      question
    })
  }

  return parsed
}

/**
 * Handle an inbound `clarify` server→client request for hermesweb.
 * Parks the card via setClarifyRequest; the inline ClarifyTool answers
 * through respondToServerRequest (JSON-RPC response frame).
 *
 * Hermes ≥0.21 always sends batch shape (`questions[]`) on the wire, even for
 * one question. A single entry is parked as a normal single-question card
 * (choices preserved). Multi-question batches are flattened into one free-text
 * prompt so the hermes-ui single-question card can still answer; the response
 * uses `{ answers: { qid: text } }` for every qid.
 */
export function handleClarifyServerRequest(request: ServerRequest): boolean {
  if (request.method !== 'clarify') {
    return false
  }

  const p = request.params
  const sessionId = typeof p.session_id === 'string' ? p.session_id : null
  const rawQuestions = Array.isArray(p.questions) ? p.questions : null

  if (rawQuestions && rawQuestions.length > 0) {
    const parsed = parseWireQuestions(rawQuestions)

    if (parsed.length === 0) {
      request.respond({ answers: {} })

      return true
    }

    // One-entry batch ≡ single clarify: keep choices and avoid the flatten
    // wrapper so the card matches tool.args and does not look duplicated.
    if (parsed.length === 1) {
      const only = parsed[0]!
      batchQids.set(request.id, [only.qid])
      rememberServerRequest(request)
      setClarifyRequest({
        choices: only.choices,
        question: only.question,
        requestId: request.id,
        sessionId
      })

      return true
    }

    batchQids.set(
      request.id,
      parsed.map(entry => entry.qid)
    )
    rememberServerRequest(request)
    setClarifyRequest({
      choices: null,
      question: `Please answer each item (one reply covers all):\n${parsed
        .map((entry, index) => `${index + 1}. ${entry.question}`)
        .join('\n')}`,
      requestId: request.id,
      sessionId
    })

    return true
  }

  const question = typeof p.question === 'string' ? p.question.trim() : ''

  if (!question) {
    request.respond({ answer: '' })

    return true
  }

  const rawChoices = p.choices
  const choices = Array.isArray(rawChoices)
    ? rawChoices.filter((c): c is string => typeof c === 'string' && c.trim().length > 0)
    : null

  rememberServerRequest(request)
  setClarifyRequest({
    choices: choices && choices.length > 0 ? choices : null,
    question,
    requestId: request.id,
    sessionId
  })

  return true
}
