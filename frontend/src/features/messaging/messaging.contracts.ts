import type { ContactUser } from '@/features/contacts/contacts.contracts'

export interface PersistedMessage {
  id: string
  conversationId: string
  body: string
  insertedAt: string
  sender: ContactUser
}

export interface MessageAck {
  message: PersistedMessage
  clientRef: string | null
}

export type MessageSendErrorReason = 'validation_error' | 'rate_limited' | 'unauthorized' | 'unknown_event'

export interface MessageSendError {
  reason: MessageSendErrorReason
  clientRef: string | null
  fields?: Record<string, string[]>
  retryAfterMs?: number
}

export interface ConversationUpdated {
  conversationId: string
  lastMessage: {
    preview: string
    senderId: string
    insertedAt: string
  }
  unread: boolean
}

export interface MembershipRevoked {
  conversationId: string
}

export function decodePersistedMessage(payload: unknown): PersistedMessage {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    conversationId: requireString(data.conversation_id),
    body: requireString(data.body),
    insertedAt: requireString(data.inserted_at),
    sender: decodeUser(data.sender),
  }
}

export function decodeMessageAck(payload: unknown): MessageAck {
  const data = requireRecord(payload)

  return {
    message: decodePersistedMessage(data.message),
    clientRef: requireNullableString(data.client_ref),
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
    clientRef: requireNullableString(data.client_ref),
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

function decodeUser(payload: unknown): ContactUser {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    username: requireString(data.username),
    name: requireString(data.name),
    lastSeenAt: requireNullableString(data.last_seen_at),
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

function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('Expected object')
  }

  return value as Record<string, unknown>
}

function requireString(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('Expected string')
  }

  return value
}

function requireNullableString(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null
  }

  return requireString(value)
}

function requireBoolean(value: unknown): boolean {
  if (typeof value !== 'boolean') {
    throw new Error('Expected boolean')
  }

  return value
}
