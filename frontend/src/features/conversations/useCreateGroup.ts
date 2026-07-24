import { storeToRefs } from 'pinia'
import { shallowRef, toValue, type MaybeRefOrGetter, type Ref } from 'vue'

import type { ConversationRecord } from './conversations.contracts'
import { conversationErrorMessage } from './conversations.error'
import { useConversationsStore } from './conversations.store'

interface UseCreateGroupOptions {
  token: MaybeRefOrGetter<string | null>
  error: Ref<string | null>
}

export function useCreateGroup({ token, error }: UseCreateGroupOptions) {
  const conversationsStore = useConversationsStore()
  const { isSavingGroup: isSubmitting } = storeToRefs(conversationsStore)
  const name = shallowRef('')
  const selectedContactIds = shallowRef<Set<string>>(new Set())

  function toggleContact(userId: string): void {
    const nextIds = new Set(selectedContactIds.value)

    if (nextIds.has(userId)) {
      nextIds.delete(userId)
    } else {
      nextIds.add(userId)
    }

    selectedContactIds.value = nextIds
  }

  async function submit(): Promise<ConversationRecord | null> {
    const currentToken = toValue(token)

    if (!currentToken || isSubmitting.value) {
      return null
    }

    if (!name.value.trim()) {
      error.value = 'Informe o nome do grupo.'
      return null
    }

    if (selectedContactIds.value.size === 0) {
      error.value = 'Selecione pelo menos um contato.'
      return null
    }

    error.value = null

    try {
      const conversation = await conversationsStore.createGroup(
        name.value,
        Array.from(selectedContactIds.value),
        currentToken,
      )
      selectedContactIds.value = new Set()
      name.value = ''
      return conversation
    } catch (submitError) {
      error.value = conversationErrorMessage(submitError)
      return null
    }
  }

  return {
    error,
    isSubmitting,
    name,
    selectedContactIds,
    submit,
    toggleContact,
  }
}
