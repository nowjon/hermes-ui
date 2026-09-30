import type { ServerRequest } from '@hermes/shared'

import { setApprovalRequest } from '@/store/prompts'
import { rememberServerRequest, respondToServerRequest } from '@/store/server-requests'

/**
 * Map session_id → JSON-RPC server request id for live `approval` frames.
 * hermes-ui's ApprovalRequest atom is still session-keyed (legacy event shape);
 * answers must go back on the original request id.
 */
const approvalRequestIds = new Map<string, string>()

function sessionKey(sessionId: string | null | undefined): string {
  return sessionId ?? ''
}

/**
 * Handle an inbound `approval` server→client request for hermesweb.
 * Parks the card via setApprovalRequest; ApprovalBar / native actions answer
 * through respondToApprovalServerRequest (JSON-RPC response frame).
 */
export function handleApprovalServerRequest(request: ServerRequest): boolean {
  if (request.method !== 'approval') {
    return false
  }

  const p = request.params
  const sessionId = typeof p.session_id === 'string' ? p.session_id : null
  const command = typeof p.command === 'string' ? p.command : ''
  const description =
    typeof p.description === 'string' && p.description.trim().length > 0
      ? p.description
      : 'dangerous command'

  rememberServerRequest(request)
  approvalRequestIds.set(sessionKey(sessionId), request.id)
  setApprovalRequest({
    // false only when tirith / protected-instruction forbids permanent allow.
    allowPermanent: p.allow_permanent !== false,
    command,
    description,
    sessionId
  })

  return true
}

/** Answer a parked approval via the open server→client request. */
export function respondToApprovalServerRequest(
  sessionId: string | null | undefined,
  choice: string,
  all?: boolean
): boolean {
  const key = sessionKey(sessionId)
  const requestId = approvalRequestIds.get(key)

  if (!requestId) {
    return false
  }

  const result: Record<string, unknown> = { choice }

  if (all !== undefined) {
    result.all = all
  }

  if (!respondToServerRequest(requestId, result)) {
    return false
  }

  approvalRequestIds.delete(key)

  return true
}

export function clearApprovalServerRequestId(sessionId: string | null | undefined): void {
  approvalRequestIds.delete(sessionKey(sessionId))
}
