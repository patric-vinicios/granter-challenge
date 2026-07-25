import type { PersistedMessage } from './messaging.contracts'

export interface ConversationHistory {
  messages: PersistedMessage[]
  nextCursor: string | null
  hasMore: boolean
  isLoadingInitial: boolean
  isLoadingOlder: boolean
  didLoadInitial: boolean
  error: string | null
}

export function createEmptyConversationHistory(): ConversationHistory {
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
