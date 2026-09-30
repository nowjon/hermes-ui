// Billing subsystem intentionally omitted from the web build (see UPSTREAM.md).
export {
  APPROVAL_RESPOND_TIMEOUT_MS,
  type ConnectionState,
  type GatewayClientOptions,
  GatewayEventHub,
  isGatewayWebSocketUrl,
  JsonRpcGatewayClient,
  type WebSocketLike
} from './json-rpc-gateway'
export type { GatewayEvent, GatewayEventName } from './gateway-events'
export {
  DEFAULT_HEARTBEAT_DEADLINE_MS,
  DEFAULT_HEARTBEAT_INTERVAL_MS,
  type GatewayRequestId,
  JSON_RPC_INTERNAL_ERROR,
  JSON_RPC_METHOD_NOT_FOUND,
  JSON_RPC_SESSION_NOT_SHOWN,
  JsonRpcGatewayError,
  type JsonRpcFrame,
  type ServerRequest,
  type ServerRequestHandler,
  type ServerRequestParams
} from './json-rpc-channel'
export {
  buildHermesWebSocketUrl,
  type GatewayAuthMode,
  GatewayReauthRequiredError,
  type GatewayWsConnection,
  type GatewayWsUrlResult,
  type HermesWebSocketUrlOptions,
  isGatewayReauthRequired,
  resolveGatewayWsUrl,
  type ResolveGatewayWsUrlDeps,
  type WebSocketAuthParam
} from './websocket-url'
export {
  isStableOpen,
  RECONNECT_STABLE_OPEN_MS,
  reconnectBackoffDelayMs,
  type ReconnectBackoffOptions
} from './reconnect-backoff'
