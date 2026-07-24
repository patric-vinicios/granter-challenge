import { storeToRefs } from 'pinia'
import { computed, toRef, toValue, watch, type MaybeRefOrGetter } from 'vue'

import { useMessagesStore } from './messaging.store'

interface ConversationIdentity {
  id: string
}

interface UseConversationHistoryOptions {
  token: MaybeRefOrGetter<string | null>
  /**
   * The explicit inbox selection. It determines whether a backend conversation
   * exists and should trigger history loading.
   */
  selectedConversationId: MaybeRefOrGetter<string | null>
  /**
   * The conversation currently rendered after the view applies its fallback.
   * It keeps pagination and visible state aligned with the ChatPanel.
   */
  displayedConversationId: MaybeRefOrGetter<string>
  persistedConversationSources: readonly MaybeRefOrGetter<readonly ConversationIdentity[]>[]
}

export function useConversationHistory({
  token,
  selectedConversationId,
  displayedConversationId,
  persistedConversationSources,
}: UseConversationHistoryOptions) {
  const messagesStore = useMessagesStore()
  const { historyByConversationId } = storeToRefs(messagesStore)
  const tokenRef = toRef(token)
  const selectedPersistedConversationId = computed(() => {
    const conversationId = toValue(selectedConversationId)

    if (!conversationId) {
      return null
    }

    return persistedConversationSources.some((source) =>
      toValue(source).some((conversation) => conversation.id === conversationId),
    )
      ? conversationId
      : null
  })
  const state = computed(
    () => historyByConversationId.value[toValue(displayedConversationId)] ?? emptyHistory(),
  )

  watch(
    [selectedPersistedConversationId, tokenRef],
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
    const currentToken = toValue(token)

    if (!currentToken) {
      return
    }

    void messagesStore.loadOlder(toValue(displayedConversationId), currentToken)
  }

  function refresh(): void {
    const currentToken = toValue(token)
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
