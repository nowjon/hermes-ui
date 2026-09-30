import { useStore } from '@nanostores/react'
import { type FC, useCallback, useMemo, useState } from 'react'

import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { useI18n } from '@/i18n'
import { clearClarifyBatchQids, getClarifyBatchQids } from '@/lib/clarify-server-request'
import { triggerHaptic } from '@/lib/haptics'
import { Loader2, MessageQuestion } from '@/lib/icons'
import { cn } from '@/lib/utils'
import { $clarifyRequest, clearClarifyRequest } from '@/store/clarify'
import { $gateway } from '@/store/gateway'
import { notifyError } from '@/store/notifications'
import { respondToServerRequest } from '@/store/server-requests'

/**
 * Floating clarify card when the inline ClarifyTool is missing or stuck.
 *
 * Hermes ≥0.21 delivers clarify as a server→client request. The inline tool
 * card only mounts when a `clarify` tool part is in the transcript AND the
 * parked question string matches tool.args — batch wire shape often differs,
 * leaving the user with no way to answer. This fallback always surfaces the
 * parked request for the active session (same idea as PendingApprovalFallback).
 */
export const PendingClarifyFallback: FC = () => {
  const { t } = useI18n()
  const copy = t.assistant.clarify
  const request = useStore($clarifyRequest)
  const gateway = useStore($gateway)
  const [draft, setDraft] = useState('')
  const [selectedChoice, setSelectedChoice] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const choices = useMemo(() => request?.choices ?? [], [request?.choices])
  const hasChoices = choices.length > 0
  const trimmedDraft = draft.trim()
  const pendingAnswer = selectedChoice ?? (trimmedDraft || null)

  const respond = useCallback(
    async (answer: string) => {
      if (!request?.requestId) {
        return
      }

      if (!gateway) {
        notifyError(new Error(copy.gatewayDisconnected), copy.sendFailed)

        return
      }

      setSubmitting(true)

      try {
        const batchQids = getClarifyBatchQids(request.requestId)
        const result = batchQids?.length
          ? { answers: Object.fromEntries(batchQids.map(qid => [qid, answer])) }
          : { answer }

        if (!respondToServerRequest(request.requestId, result)) {
          await gateway.request<{ ok?: boolean }>('clarify.respond', {
            request_id: request.requestId,
            answer
          })
        }

        clearClarifyBatchQids(request.requestId)
        triggerHaptic('submit')
        clearClarifyRequest(request.requestId, request.sessionId)
        setDraft('')
        setSelectedChoice(null)
      } catch (error) {
        notifyError(error, copy.sendFailed)
        setSubmitting(false)
      }
    },
    [copy.gatewayDisconnected, copy.sendFailed, gateway, request]
  )

  if (!request) {
    return null
  }

  return (
    <div
      className="pointer-events-none absolute left-1/2 z-30 w-[calc(100%-2rem)] max-w-2xl -translate-x-1/2"
      data-slot="clarify-fallback"
      style={{ bottom: 'calc(var(--composer-measured-height) + var(--status-stack-measured-height) + 0.875rem)' }}
    >
      <div className="pointer-events-auto rounded-xl border border-primary/30 bg-(--ui-chat-surface-background) px-3 py-3 shadow-lg backdrop-blur-xl [-webkit-backdrop-filter:blur(1rem)]">
        <div className="mb-2 flex min-w-0 items-center gap-2 text-sm text-primary">
          <MessageQuestion className="size-4 shrink-0" />
          <span className="shrink-0 font-medium">Asking a question</span>
        </div>
        <p className="mb-3 whitespace-pre-wrap text-sm text-(--ui-text)">{request.question}</p>
        {hasChoices ? (
          <div className="mb-3 flex flex-wrap gap-2">
            {choices.map(choice => (
              <Button
                key={choice}
                disabled={submitting}
                onClick={() => {
                  setDraft('')
                  setSelectedChoice(choice)
                }}
                size="sm"
                type="button"
                variant={selectedChoice === choice ? 'default' : 'outline'}
              >
                {choice}
              </Button>
            ))}
          </div>
        ) : null}
        <Textarea
          className={cn('mb-2 min-h-16 resize-y')}
          disabled={submitting}
          onChange={event => {
            setSelectedChoice(null)
            setDraft(event.target.value)
          }}
          placeholder={copy.placeholder}
          value={draft}
        />
        <div className="flex justify-end gap-2">
          <Button
            disabled={submitting || !pendingAnswer}
            onClick={() => {
              if (pendingAnswer) {
                void respond(pendingAnswer)
              }
            }}
            size="sm"
            type="button"
          >
            {submitting ? <Loader2 className="size-3.5 animate-spin" /> : copy.continueLabel}
          </Button>
        </div>
      </div>
    </div>
  )
}
