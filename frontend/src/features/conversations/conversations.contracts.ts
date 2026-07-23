import type { ContactUser } from '@/features/contacts/contacts.contracts'

export interface PrivateConversation {
  id: string
  type: 'private'
  lastReadAt: string | null
  counterpart: ContactUser
}

export interface GroupConversation {
  id: string
  type: 'group'
  name: string
  creatorId: string
  memberCount: number
  lastReadAt: string | null
  members: ContactUser[]
}

export type ConversationRecord = PrivateConversation | GroupConversation

export function decodeConversation(payload: unknown): ConversationRecord {
  const data = requireRecord(payload)

  return decodeConversationRecord(data.conversation)
}

function decodeConversationRecord(payload: unknown): ConversationRecord {
  const data = requireRecord(payload)
  const type = requireString(data.type)

  if (type === 'private') {
    return {
      id: requireString(data.id),
      type,
      lastReadAt: requireNullableString(data.last_read_at),
      counterpart: decodeUser(data.counterpart),
    }
  }

  if (type === 'group') {
    const members = data.members

    if (!Array.isArray(members)) {
      throw new Error('Expected members array')
    }

    return {
      id: requireString(data.id),
      type,
      name: requireString(data.name),
      creatorId: requireString(data.creator_id),
      memberCount: requireNumber(data.member_count),
      lastReadAt: requireNullableString(data.last_read_at),
      members: members.map(decodeUser),
    }
  }

  throw new Error('Unsupported conversation type')
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

function requireNumber(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error('Expected number')
  }

  return value
}
