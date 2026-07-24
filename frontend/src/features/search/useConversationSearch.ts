import { computed, ref, toRef, watch, type MaybeRefOrGetter } from 'vue'

import type { ConversationSearchStatus } from '@/types/search'

import { searchConversationMessages } from './search.api'
import type { ConversationSearchHit, ConversationSearchResult } from './search.contracts'

export type { ConversationSearchStatus } from '@/types/search'

interface UseConversationSearchOptions {
  token: MaybeRefOrGetter<string | null>
  conversationId: MaybeRefOrGetter<string | null>
  query: MaybeRefOrGetter<string>
}

export function useConversationSearch({ token, conversationId, query }: UseConversationSearchOptions) {
  const tokenRef = toRef(token)
  const conversationIdRef = toRef(conversationId)
  const queryRef = toRef(query)
  const status = ref<ConversationSearchStatus>('idle')
  const error = ref<string | null>(null)
  const result = ref<ConversationSearchResult | null>(null)
  const activeIndex = ref(0)

  const matches = computed(() => result.value?.matches ?? [])
  const activeHit = computed<ConversationSearchHit | null>(() => matches.value[activeIndex.value] ?? null)
  const totalMatches = computed(() => result.value?.totalMatches ?? 0)
  const truncated = computed(() => result.value?.truncated ?? false)

  watch(
    [tokenRef, conversationIdRef, queryRef],
    ([currentToken, currentConversationId, rawQuery], _previous, onCleanup) => {
      const trimmedQuery = rawQuery.trim()
      activeIndex.value = 0

      if (!trimmedQuery) {
        reset()
        return
      }

      if (trimmedQuery.length < 2) {
        result.value = null
        status.value = 'validation'
        error.value = 'Digite pelo menos 2 caracteres.'
        return
      }

      if (trimmedQuery.length > 100) {
        result.value = null
        status.value = 'validation'
        error.value = 'Digite no máximo 100 caracteres.'
        return
      }

      if (!currentToken) {
        result.value = null
        status.value = 'validation'
        error.value = 'Entre para buscar no servidor.'
        return
      }

      if (!currentConversationId) {
        reset()
        return
      }

      const controller = new AbortController()
      status.value = 'loading'
      error.value = null

      searchConversationMessages(currentConversationId, trimmedQuery, currentToken, controller.signal)
        .then((nextResult) => {
          if (controller.signal.aborted) {
            return
          }

          result.value = nextResult
          status.value = 'success'
          error.value = null
        })
        .catch((searchError: unknown) => {
          if (controller.signal.aborted) {
            return
          }

          result.value = null
          status.value = 'error'
          error.value = searchError instanceof Error ? searchError.message : 'Não foi possível buscar mensagens.'
        })

      onCleanup(() => controller.abort())
    },
    { immediate: true },
  )

  function selectNext(): void {
    if (matches.value.length === 0) {
      return
    }

    activeIndex.value = (activeIndex.value + 1) % matches.value.length
  }

  function selectPrevious(): void {
    if (matches.value.length === 0) {
      return
    }

    activeIndex.value = activeIndex.value === 0 ? matches.value.length - 1 : activeIndex.value - 1
  }

  function reset(): void {
    result.value = null
    status.value = 'idle'
    error.value = null
  }

  return {
    activeHit,
    activeIndex,
    error,
    matches,
    selectNext,
    selectPrevious,
    status,
    totalMatches,
    truncated,
  }
}
