import { storeToRefs } from 'pinia'
import { computed, type Ref } from 'vue'

import type { GroupConversation } from './conversations.contracts'
import { conversationErrorMessage } from './conversations.error'
import { useConversationsStore } from './conversations.store'

interface UseGroupDetailsOptions {
  token: Readonly<Ref<string | null>>
  currentUserId: Readonly<Ref<string | null>>
  selectedConversationId: Readonly<Ref<string | null>>
  error: Ref<string | null>
}

type ConversationType = 'private' | 'group'

export function useGroupDetails({
  token,
  currentUserId,
  selectedConversationId,
  error,
}: UseGroupDetailsOptions) {
  const conversationsStore = useConversationsStore()
  const { conversations } = storeToRefs(conversationsStore)
  const selectedGroupConversation = computed<GroupConversation | null>(() => {
    const conversation = conversations.value.find(
      (item) => item.id === selectedConversationId.value && item.type === 'group',
    )

    return conversation?.type === 'group' ? conversation : null
  })

  async function open(conversationId: string, conversationType: ConversationType): Promise<boolean> {
    const currentToken = token.value
    const selectedGroup = selectedGroupConversation.value

    if (selectedGroup) {
      error.value = null
      return true
    }

    if (!currentToken || conversationType !== 'group') {
      return false
    }

    try {
      await conversationsStore.loadConversation(conversationId, currentToken)
      error.value = null
      return true
    } catch (openError) {
      error.value = conversationErrorMessage(openError)
      return false
    }
  }

  async function addMember(userId: string): Promise<void> {
    const currentToken = token.value
    const group = selectedGroupConversation.value

    if (!currentToken || !group) {
      return
    }

    try {
      await conversationsStore.addMembers(group.id, [userId], currentToken)
      error.value = null
    } catch (addError) {
      error.value = conversationErrorMessage(addError)
    }
  }

  async function removeMember(userId: string): Promise<void> {
    const currentToken = token.value
    const group = selectedGroupConversation.value

    if (!currentToken || !group) {
      return
    }

    try {
      await conversationsStore.removeMember(group.id, userId, currentToken)
      error.value = null
    } catch (removeError) {
      error.value = conversationErrorMessage(removeError)
    }
  }

  async function leave(): Promise<string | null> {
    const currentToken = token.value
    const userId = currentUserId.value
    const group = selectedGroupConversation.value

    if (!currentToken || !userId || !group) {
      return null
    }

    try {
      await conversationsStore.leave(group.id, currentToken)
      error.value = null
      return group.id
    } catch (leaveError) {
      error.value = conversationErrorMessage(leaveError)
      return null
    }
  }

  return {
    selectedGroupConversation,
    open,
    addMember,
    removeMember,
    leave,
  }
}
