import { requestJson } from '@/shared/api/httpClient'

import { type ConversationRecord, decodeConversation } from './conversations.contracts'

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
