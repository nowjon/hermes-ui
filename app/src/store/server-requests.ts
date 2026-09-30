import type { ServerRequest } from '@hermes/shared'

/**
 * Live server→client requests (`tui_gateway/server_requests.py`) keyed by
 * request id. Cards answer through `respondToServerRequest`, which routes the
 * JSON-RPC response back over the socket the request arrived on.
 */
const open = new Map<string, ServerRequest>()

export function rememberServerRequest(request: ServerRequest): void {
  open.set(request.id, request)
}

export function forgetServerRequest(id: string): void {
  open.delete(id)
}

/** Answer request `id`. False when nothing is open under that id. */
export function respondToServerRequest(id: string | undefined, result: Record<string, unknown>): boolean {
  const request = id ? open.get(id) : undefined

  if (!request) {
    return false
  }

  open.delete(id!)
  request.respond(result)

  return true
}

export function hasOpenServerRequest(id: string): boolean {
  return open.has(id)
}

export function resetServerRequestsForTests(): void {
  open.clear()
}
