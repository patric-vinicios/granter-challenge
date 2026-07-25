import type { ChatUser } from '@/types/user'
import {
  requireBoolean,
  requireNullableNumber,
  requireNumber,
  requireOptionalNullableString,
  requireRecord,
  requireString,
} from '@/shared/contracts/decoders'
import { decodeChatUser } from '@/shared/contracts/user'

interface PrivateConversation {
  id: string
  type: 'private'
  lastReadAt: string | null
  counterpart: ChatUser
}

export interface GroupConversation {
  id: string
  type: 'group'
  name: string
  creatorId: string
  memberCount: number
  lastReadAt: string | null
  members: ChatUser[]
}

export type ConversationRecord = PrivateConversation | GroupConversation

interface InboxLastMessage {
  id: string
  body: string
  senderId: string
  insertedAt: string
}

export interface InboxConversationSummary {
  id: string
  type: 'private' | 'group'
  title: string
  counterpart: ChatUser | null
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
      lastReadAt: requireOptionalNullableString(data.last_read_at),
      counterpart: decodeChatUser(data.counterpart),
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
      lastReadAt: requireOptionalNullableString(data.last_read_at),
      members: members.map((member) => decodeChatUser(member)),
    }
  }

  throw new Error('Unsupported conversation type')
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
    counterpart: data.counterpart === null ? null : decodeChatUser(data.counterpart),
    memberCount: requireNullableNumber(data.member_count),
    lastMessage: data.last_message === null ? null : decodeInboxLastMessage(data.last_message),
    unreadCount: requireNumber(data.unread_count),
    unreadOverflow: requireBoolean(data.unread_overflow),
    lastReadAt: requireOptionalNullableString(data.last_read_at),
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

function requireZero(value: unknown): 0 {
  if (value !== 0) {
    throw new Error('Expected zero')
  }

  return 0
}
