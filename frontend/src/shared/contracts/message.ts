import type { PersistedMessage } from '@/types/message'

import { requireRecord, requireString } from './decoders'
import { decodeChatUser } from './user'

export function decodePersistedMessage(payload: unknown): PersistedMessage {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    conversationId: requireString(data.conversation_id),
    body: requireString(data.body),
    insertedAt: requireString(data.inserted_at),
    sender: decodeChatUser(data.sender),
  }
}
