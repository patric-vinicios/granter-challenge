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
