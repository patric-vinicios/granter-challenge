import { computed, shallowRef, type MaybeRefOrGetter } from 'vue'

import type { SearchMatchOffset } from './search.contracts'
import { useConversationSearch } from './useConversationSearch'

interface UseConversationSearchPanelOptions {
  token: MaybeRefOrGetter<string | null>
  conversationId: MaybeRefOrGetter<string | null>
}

export function useConversationSearchPanel({
  token,
  conversationId,
}: UseConversationSearchPanelOptions) {
  const isOpen = shallowRef(false)
  const term = shallowRef('')
  const activeQuery = computed(() => (isOpen.value ? term.value : ''))
  const {
    activeHit,
    error,
    selectNext,
    selectPrevious,
    status,
    totalMatches,
    truncated,
  } = useConversationSearch({
    token,
    conversationId,
    query: activeQuery,
  })
  const activePosition = computed<number | null>(() => activeHit.value?.position ?? null)
  const activeMessageId = computed<string | null>(() => activeHit.value?.message.id ?? null)
  const activeMatchOffsets = computed<SearchMatchOffset[]>(
    () => activeHit.value?.matchOffsets ?? [],
  )

  function open(): void {
    term.value = ''
    isOpen.value = true
  }

  function close(): void {
    isOpen.value = false
    term.value = ''
  }

  function closeOnFocusOut(event: FocusEvent): void {
    const nextTarget = event.relatedTarget

    if (nextTarget instanceof Node && event.currentTarget instanceof Node) {
      if (event.currentTarget.contains(nextTarget)) {
        return
      }
    }

    close()
  }

  return {
    activeHit,
    activeMatchOffsets,
    activeMessageId,
    activePosition,
    error,
    isOpen,
    term,
    totalMatches,
    truncated,
    status,
    close,
    closeOnFocusOut,
    open,
    selectNext,
    selectPrevious,
  }
}
