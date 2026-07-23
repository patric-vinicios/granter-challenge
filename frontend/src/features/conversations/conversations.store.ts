import { defineStore } from 'pinia'
import { ref } from 'vue'

import { openPrivateConversation as openPrivateConversationRequest } from './conversations.api'
import type { ConversationRecord } from './conversations.contracts'

export const useConversationsStore = defineStore('conversations', () => {
  const conversations = ref<ConversationRecord[]>([])
  const pendingPrivateUserIds = ref<Set<string>>(new Set())

  async function openPrivate(userId: string, token: string): Promise<ConversationRecord> {
    pendingPrivateUserIds.value = new Set(pendingPrivateUserIds.value).add(userId)

    try {
      const conversation = await openPrivateConversationRequest(userId, token)
      upsertConversation(conversation)

      return conversation
    } finally {
      const nextIds = new Set(pendingPrivateUserIds.value)
      nextIds.delete(userId)
      pendingPrivateUserIds.value = nextIds
    }
  }

  function reset(): void {
    conversations.value = []
    pendingPrivateUserIds.value = new Set()
  }

  function upsertConversation(conversation: ConversationRecord): void {
    const index = conversations.value.findIndex((item) => item.id === conversation.id)

    if (index >= 0) {
      const nextConversations = [...conversations.value]
      nextConversations[index] = conversation
      conversations.value = nextConversations
      return
    }

    conversations.value = [conversation, ...conversations.value]
  }

  return {
    conversations,
    pendingPrivateUserIds,
    openPrivate,
    reset,
  }
})
