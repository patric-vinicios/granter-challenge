import { storeToRefs } from 'pinia'
import { computed, shallowRef, toRef, toValue, watch, type MaybeRefOrGetter, type Ref } from 'vue'

import { useDebouncedValue } from '@/shared/reactivity/useDebouncedValue'

import { conversationErrorMessage } from './conversations.error'
import { useConversationsStore } from './conversations.store'

interface InboxListItem {
  id: string
}

interface UseInboxListOptions {
  token: MaybeRefOrGetter<string | null>
  items: MaybeRefOrGetter<readonly InboxListItem[]>
  selectedConversationId: Ref<string | null>
  query?: Ref<string>
}

export function useInboxList({ token, items, selectedConversationId, query: querySource }: UseInboxListOptions) {
  const conversationsStore = useConversationsStore()
  const tokenRef = toRef(token)
  const itemsRef = toRef(items)
  const selectedConversationIdRef = toRef(selectedConversationId)
  const {
    inboxLoadError: error,
    inboxLoadState,
    inboxSummaries,
    pendingReadIds,
  } = storeToRefs(conversationsStore)
  const query = querySource ?? shallowRef('')
  const debouncedQuery = useDebouncedValue(query, {
    delayMs: 800,
    immediateWhen: (value) => value.trim() === '',
  })
  const isLoading = computed(() => inboxLoadState.value === 'loading' && inboxSummaries.value.length === 0)
  const isEmpty = computed(
    () => Boolean(toValue(token)) && inboxLoadState.value === 'success' && toValue(items).length === 0,
  )

  watch(
    [tokenRef, debouncedQuery],
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
    [itemsRef, tokenRef, query],
    ([currentItems, currentToken, currentQuery]) => {
      if (!currentToken) {
        return
      }

      const selectedConversationIsVisible = currentItems.some((item) => item.id === selectedConversationIdRef.value)

      if (selectedConversationIsVisible) {
        return
      }

      if (currentQuery.trim()) {
        selectedConversationIdRef.value = null
        return
      }

      selectedConversationIdRef.value = currentItems[0]?.id ?? null
    },
    { immediate: true },
  )

  async function select(conversationId: string): Promise<void> {
    selectedConversationIdRef.value = conversationId

    const currentToken = toValue(token)
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
    const currentToken = toValue(token)

    if (!currentToken) {
      return
    }

    await conversationsStore.loadInbox(currentToken, undefined, debouncedQuery.value)
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
