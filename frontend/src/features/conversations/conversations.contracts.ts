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

export interface InboxLastMessage {
  id: string
  body: string
  senderId: string
  insertedAt: string
}

export interface InboxConversationSummary {
  id: string
  type: 'private' | 'group'
  title: string
  counterpart: ContactUser | null
  memberCount: number | null
  lastMessage: InboxLastMessage | null
  unreadCount: number
  unreadOverflow: boolean
  lastReadAt: string | null
}

export interface MarkReadResult {
  conversationId: string
  lastReadAt: string
  unreadCount: 0
}

export function decodeConversation(payload: unknown): ConversationRecord {
  const data = requireRecord(payload)

  return decodeConversationRecord(data.conversation)
}

export function decodeInboxConversations(payload: unknown): InboxConversationSummary[] {
  const data = requireRecord(payload)
  const conversations = data.conversations

  if (!Array.isArray(conversations)) {
    throw new Error('Expected conversations array')
  }

  return conversations.map(decodeInboxConversation)
}

export function decodeMarkReadResult(payload: unknown): MarkReadResult {
  const data = requireRecord(payload)

  return {
    conversationId: requireString(data.conversation_id),
    lastReadAt: requireString(data.last_read_at),
    unreadCount: requireZero(data.unread_count),
  }
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
    online: requireOptionalBoolean(data.online),
  }
}

function decodeInboxConversation(payload: unknown): InboxConversationSummary {
  const data = requireRecord(payload)
  const type = requireString(data.type)

  if (type !== 'private' && type !== 'group') {
    throw new Error('Unsupported conversation summary type')
  }

  return {
    id: requireString(data.id),
    type,
    title: requireString(data.title),
    counterpart: data.counterpart === null ? null : decodeUser(data.counterpart),
    memberCount: requireNullableNumber(data.member_count),
    lastMessage: data.last_message === null ? null : decodeInboxLastMessage(data.last_message),
    unreadCount: requireNumber(data.unread_count),
    unreadOverflow: requireBoolean(data.unread_overflow),
    lastReadAt: requireNullableString(data.last_read_at),
  }
}

function decodeInboxLastMessage(payload: unknown): InboxLastMessage {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    body: requireString(data.body),
    senderId: requireString(data.sender_id),
    insertedAt: requireString(data.inserted_at),
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

function requireNullableNumber(value: unknown): number | null {
  if (value === null) {
    return null
  }

  return requireNumber(value)
}

function requireBoolean(value: unknown): boolean {
  if (typeof value !== 'boolean') {
    throw new Error('Expected boolean')
  }

  return value
}

function requireOptionalBoolean(value: unknown): boolean {
  if (value === undefined) {
    return false
  }

  return requireBoolean(value)
}

function requireZero(value: unknown): 0 {
  if (value !== 0) {
    throw new Error('Expected zero')
  }

  return 0
}
