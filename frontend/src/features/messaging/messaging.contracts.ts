import type { ContactUser } from '@/features/contacts/contacts.contracts'

export interface PersistedMessage {
  id: string
  conversationId: string
  body: string
  insertedAt: string
  sender: ContactUser
}

export interface MessageHistoryPage {
  messages: PersistedMessage[]
  nextCursor: string | null
  hasMore: boolean
}

export function decodeMessageHistoryPage(payload: unknown): MessageHistoryPage {
  const data = requireRecord(payload)
  const messages = data.messages

  if (!Array.isArray(messages)) {
    throw new Error('Expected messages array')
  }

  return {
    messages: messages.map(decodeMessage),
    nextCursor: requireNullableString(data.next_cursor),
    hasMore: requireBoolean(data.has_more),
  }
}

function decodeMessage(payload: unknown): PersistedMessage {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    conversationId: requireString(data.conversation_id),
    body: requireString(data.body),
    insertedAt: requireString(data.inserted_at),
    sender: decodeUser(data.sender),
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
