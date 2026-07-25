import type { PersistedMessage } from '@/types/message'
import type { ConversationUpdated } from '@/types/realtime'
import {
  requireBoolean,
  requireOptionalNullableString,
  requireRecord,
  requireString,
} from '@/shared/contracts/decoders'
import { decodePersistedMessage } from '@/shared/contracts/message'

export type { PersistedMessage } from '@/types/message'
export type { ConversationUpdated } from '@/types/realtime'
export { decodePersistedMessage } from '@/shared/contracts/message'

export interface MessageHistoryPage {
  messages: PersistedMessage[]
  nextCursor: string | null
  hasMore: boolean
}

export interface MessageAck {
  message: PersistedMessage
  clientRef: string | null
}

type MessageSendErrorReason = 'validation_error' | 'rate_limited' | 'unauthorized' | 'unknown_event'

export interface MessageSendError {
  reason: MessageSendErrorReason
  clientRef: string | null
  fields?: Record<string, string[]>
  retryAfterMs?: number
}

export interface MembershipRevoked {
  conversationId: string
}

export function decodeMessageHistoryPage(payload: unknown): MessageHistoryPage {
  const data = requireRecord(payload)
  const messages = data.messages

  if (!Array.isArray(messages)) {
    throw new Error('Expected messages array')
  }

  return {
    messages: messages.map(decodePersistedMessage),
    nextCursor: requireOptionalNullableString(data.next_cursor),
    hasMore: requireBoolean(data.has_more),
  }
}

export function decodeMessageAck(payload: unknown): MessageAck {
  const data = requireRecord(payload)

  return {
    message: decodePersistedMessage(data.message),
    clientRef: requireOptionalNullableString(data.client_ref),
  }
}

export function decodeMessageSendError(payload: unknown): MessageSendError {
  const data = requireRecord(payload)
  const reason = requireString(data.reason)

  if (!isMessageSendErrorReason(reason)) {
    throw new Error('Unsupported message send error')
  }

  return {
    reason,
    clientRef: requireOptionalNullableString(data.client_ref),
    fields: decodeFields(data.fields),
    retryAfterMs: decodeOptionalNumber(data.retry_after_ms),
  }
}

export function decodeConversationUpdated(payload: unknown): ConversationUpdated {
  const data = requireRecord(payload)
  const lastMessage = requireRecord(data.last_message)

  return {
    conversationId: requireString(data.conversation_id),
    lastMessage: {
      preview: requireString(lastMessage.preview),
      senderId: requireString(lastMessage.sender_id),
      insertedAt: requireString(lastMessage.inserted_at),
    },
    unread: requireBoolean(data.unread),
  }
}

export function decodeMembershipRevoked(payload: unknown): MembershipRevoked {
  const data = requireRecord(payload)

  return {
    conversationId: requireString(data.conversation_id),
  }
}

function decodeFields(payload: unknown): Record<string, string[]> | undefined {
  if (payload === undefined) {
    return undefined
  }

  const data = requireRecord(payload)
  const fields: Record<string, string[]> = {}

  for (const [key, value] of Object.entries(data)) {
    if (!Array.isArray(value) || !value.every((item) => typeof item === 'string')) {
      throw new Error('Expected field messages')
    }

    fields[key] = value
  }

  return fields
}

function decodeOptionalNumber(payload: unknown): number | undefined {
  if (payload === undefined) {
    return undefined
  }

  if (typeof payload !== 'number' || !Number.isFinite(payload)) {
    throw new Error('Expected number')
  }

  return payload
}

function isMessageSendErrorReason(value: string): value is MessageSendErrorReason {
  return value === 'validation_error' || value === 'rate_limited' || value === 'unauthorized' || value === 'unknown_event'
}
