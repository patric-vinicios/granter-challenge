import { requestJson } from '@/shared/api/httpClient'

import {
  type ConversationRecord,
  type InboxConversationSummary,
  type MarkReadResult,
  decodeConversation,
  decodeInboxConversations,
  decodeMarkReadResult,
} from './conversations.contracts'

export function listInboxConversations(
  token: string,
  options: { query?: string; signal?: AbortSignal } = {},
): Promise<InboxConversationSummary[]> {
  return requestJson('/conversations' + inboxQueryString(options.query), {
    token,
    signal: options.signal,
    decode: decodeInboxConversations,
  })
}

function inboxQueryString(query: string | undefined): string {
  const trimmed = query?.trim()

  if (!trimmed) {
    return ''
  }

  const params = new URLSearchParams({ q: trimmed })

  return `?${params.toString()}`
}

export function markConversationRead(
  conversationId: string,
  token: string,
  signal?: AbortSignal,
): Promise<MarkReadResult> {
  return requestJson('/conversations/' + encodeURIComponent(conversationId) + '/read', {
    method: 'POST',
    token,
    signal,
    decode: decodeMarkReadResult,
  })
}

export function getConversation(conversationId: string, token: string, signal?: AbortSignal): Promise<ConversationRecord> {
  return requestJson('/conversations/' + encodeURIComponent(conversationId), {
    token,
    signal,
    decode: decodeConversation,
  })
}

export function openPrivateConversation(
  userId: string,
  token: string,
  signal?: AbortSignal,
): Promise<ConversationRecord> {
  return requestJson('/conversations/private', {
    method: 'POST',
    body: { user_id: userId },
    token,
    signal,
    decode: decodeConversation,
  })
}

export function createGroupConversation(
  name: string,
  memberIds: string[],
  token: string,
  signal?: AbortSignal,
): Promise<ConversationRecord> {
  return requestJson('/conversations/groups', {
    method: 'POST',
    body: { name, member_ids: memberIds },
    token,
    signal,
    decode: decodeConversation,
  })
}

export function addGroupMembers(
  conversationId: string,
  memberIds: string[],
  token: string,
  signal?: AbortSignal,
): Promise<ConversationRecord> {
  return requestJson('/conversations/' + encodeURIComponent(conversationId) + '/members', {
    method: 'POST',
    body: { member_ids: memberIds },
    token,
    signal,
    decode: decodeConversation,
  })
}

export function removeGroupMember(
  conversationId: string,
  userId: string,
  token: string,
  signal?: AbortSignal,
): Promise<void> {
  return requestJson(
    '/conversations/' + encodeURIComponent(conversationId) + '/members/' + encodeURIComponent(userId),
    {
      method: 'DELETE',
      token,
      signal,
      decode: () => undefined,
    },
  )
}

export function leaveGroup(conversationId: string, token: string, signal?: AbortSignal): Promise<void> {
  return requestJson('/conversations/' + encodeURIComponent(conversationId) + '/members/me', {
    method: 'DELETE',
    token,
    signal,
    decode: () => undefined,
  })
}
