import { formatMessageTime } from '@/shared/date/formatMessageTime'
import type { ChatMessage } from '@/types/chat'
import type { PersistedMessage } from '@/types/message'

export function toChatMessage(
  message: PersistedMessage,
  currentUserId: string | null,
): ChatMessage {
  const isOutgoing = message.sender.id === currentUserId

  return {
    id: message.id,
    side: isOutgoing ? 'out' : 'in',
    author: isOutgoing ? undefined : message.sender.name,
    text: message.body,
    time: formatMessageTime(message.insertedAt),
    insertedAt: message.insertedAt,
    wide: message.body.length > 44,
  }
}
