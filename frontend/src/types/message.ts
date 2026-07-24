import type { ChatUser } from './user'

export interface PersistedMessage {
  id: string
  conversationId: string
  body: string
  insertedAt: string
  sender: ChatUser
}
