export interface ConversationUpdated {
  conversationId: string
  lastMessage: {
    preview: string
    senderId: string
    insertedAt: string
  }
  unread: boolean
}
