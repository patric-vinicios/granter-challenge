import { storeToRefs } from 'pinia'
import { computed, shallowRef, watch, type Ref } from 'vue'

import { conversationErrorMessage } from './conversations.error'
import { useConversationsStore } from './conversations.store'

interface InboxListItem {
  id: string
}

interface UseInboxListOptions {
  token: Readonly<Ref<string | null>>
  items: Readonly<Ref<readonly InboxListItem[]>>
  selectedConversationId: Ref<string | null>
}

export function useInboxList({ token, items, selectedConversationId }: UseInboxListOptions) {
  const conversationsStore = useConversationsStore()
  const {
    inboxLoadError: error,
    inboxLoadState,
    inboxSummaries,
    pendingReadIds,
  } = storeToRefs(conversationsStore)
  const query = shallowRef('')
  const isLoading = computed(() => inboxLoadState.value === 'loading' && inboxSummaries.value.length === 0)
  const isEmpty = computed(
    () => Boolean(token.value) && inboxLoadState.value === 'success' && items.value.length === 0,
  )

  watch(
    [token, query],
    ([currentToken, currentQuery], _previous, onCleanup) => {
      if (!currentToken) {
        return
      }

      const controller = new AbortController()
      void conversationsStore.loadInbox(currentToken, controller.signal, currentQuery)
      onCleanup(() => controller.abort())
    },
    { immediate: true },
  )

  watch(
    [items, token],
    ([currentItems, currentToken]) => {
      if (!currentToken || currentItems.length === 0) {
        return
      }

      if (!currentItems.some((item) => item.id === selectedConversationId.value)) {
        selectedConversationId.value = currentItems[0].id
      }
    },
    { immediate: true },
  )

  async function select(conversationId: string): Promise<void> {
    selectedConversationId.value = conversationId

    const currentToken = token.value
    const summary = inboxSummaries.value.find((conversation) => conversation.id === conversationId)

    if (!currentToken || !summary || summary.unreadCount === 0 || pendingReadIds.value.has(conversationId)) {
      return
    }

    try {
      await conversationsStore.markRead(conversationId, currentToken)
    } catch (selectError) {
      error.value = conversationErrorMessage(selectError)
    }
  }

  async function reload(): Promise<void> {
    const currentToken = token.value

    if (!currentToken) {
      return
    }

    await conversationsStore.loadInbox(currentToken, undefined, query.value)
  }

  return {
    error,
    isEmpty,
    isLoading,
    query,
    reload,
    select,
  }
}
