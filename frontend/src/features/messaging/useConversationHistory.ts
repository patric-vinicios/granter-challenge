import { storeToRefs } from 'pinia'
import { computed, watch, type Ref } from 'vue'

import { useMessagesStore } from './messaging.store'

interface ConversationIdentity {
  id: string
}

interface UseConversationHistoryOptions {
  token: Readonly<Ref<string | null>>
  /**
   * The explicit inbox selection. It determines whether a backend conversation
   * exists and should trigger history loading.
   */
  selectedConversationId: Readonly<Ref<string | null>>
  /**
   * The conversation currently rendered after the view applies its fallback.
   * It keeps pagination and visible state aligned with the ChatPanel.
   */
  displayedConversationId: Readonly<Ref<string>>
  persistedConversationSources: readonly Readonly<Ref<readonly ConversationIdentity[]>>[]
}

export function useConversationHistory({
  token,
  selectedConversationId,
  displayedConversationId,
  persistedConversationSources,
}: UseConversationHistoryOptions) {
  const messagesStore = useMessagesStore()
  const { historyByConversationId } = storeToRefs(messagesStore)
  const selectedPersistedConversationId = computed(() => {
    const conversationId = selectedConversationId.value

    if (!conversationId) {
      return null
    }

    return persistedConversationSources.some((source) =>
      source.value.some((conversation) => conversation.id === conversationId),
    )
      ? conversationId
      : null
  })
  const state = computed(
    () => historyByConversationId.value[displayedConversationId.value] ?? emptyHistory(),
  )

  watch(
    [selectedPersistedConversationId, token],
    ([conversationId, currentToken], _previous, onCleanup) => {
      if (!conversationId || !currentToken) {
        return
      }

      const controller = new AbortController()
      void messagesStore.loadInitial(conversationId, currentToken, controller.signal)
      onCleanup(() => controller.abort())
    },
    { immediate: true },
  )

  function loadOlder(): void {
    const currentToken = token.value

    if (!currentToken) {
      return
    }

    void messagesStore.loadOlder(displayedConversationId.value, currentToken)
  }

  function refresh(): void {
    const currentToken = token.value
    const conversationId = selectedPersistedConversationId.value

    if (!currentToken || !conversationId) {
      return
    }

    void messagesStore.loadInitial(conversationId, currentToken, undefined, {
      force: true,
      silent: true,
    })
  }

  return {
    state,
    loadOlder,
    refresh,
  }
}

function emptyHistory() {
  return {
    messages: [],
    nextCursor: null,
    hasMore: false,
    isLoadingInitial: false,
    isLoadingOlder: false,
    didLoadInitial: false,
    error: null,
  }
}
