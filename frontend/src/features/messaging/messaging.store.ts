import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { listMessages } from './messaging.api'
import type { PersistedMessage } from './messaging.contracts'

interface ConversationHistory {
  messages: PersistedMessage[]
  nextCursor: string | null
  hasMore: boolean
  isLoadingInitial: boolean
  isLoadingOlder: boolean
  didLoadInitial: boolean
  error: string | null
}

function emptyHistory(): ConversationHistory {
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

export const useMessagesStore = defineStore('messages', () => {
  const histories = ref<Record<string, ConversationHistory>>({})

  const historyByConversationId = computed(() => histories.value)

  async function loadInitial(conversationId: string, token: string, signal?: AbortSignal): Promise<void> {
    const current = ensureHistory(conversationId)

    if (current.isLoadingInitial || current.didLoadInitial) {
      return
    }

    setHistory(conversationId, { ...current, isLoadingInitial: true, error: null })

    try {
      const page = await listMessages(conversationId, token, { limit: 30, signal })
      setHistory(conversationId, {
        messages: page.messages,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingInitial: false,
        isLoadingOlder: false,
        didLoadInitial: true,
        error: null,
      })
    } catch (error) {
      if (isAbortError(error)) {
        return
      }

      setHistory(conversationId, {
        ...ensureHistory(conversationId),
        isLoadingInitial: false,
        didLoadInitial: true,
        error: error instanceof Error ? error.message : 'Não foi possível carregar o histórico.',
      })
    }
  }

  async function loadOlder(conversationId: string, token: string): Promise<void> {
    const current = ensureHistory(conversationId)

    if (!current.hasMore || !current.nextCursor || current.isLoadingOlder) {
      return
    }

    setHistory(conversationId, { ...current, isLoadingOlder: true, error: null })

    try {
      const page = await listMessages(conversationId, token, { limit: 30, before: current.nextCursor })
      const latest = ensureHistory(conversationId)

      setHistory(conversationId, {
        messages: dedupeMessages([...page.messages, ...latest.messages]),
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingInitial: false,
        isLoadingOlder: false,
        didLoadInitial: true,
        error: null,
      })
    } catch (error) {
      setHistory(conversationId, {
        ...ensureHistory(conversationId),
        isLoadingOlder: false,
        error: error instanceof Error ? error.message : 'Não foi possível carregar mensagens anteriores.',
      })
    }
  }

  function reset(): void {
    histories.value = {}
  }

  function ensureHistory(conversationId: string): ConversationHistory {
    return histories.value[conversationId] ?? emptyHistory()
  }

  function setHistory(conversationId: string, history: ConversationHistory): void {
    histories.value = {
      ...histories.value,
      [conversationId]: history,
    }
  }

  return {
    histories,
    historyByConversationId,
    loadInitial,
    loadOlder,
    reset,
  }
})

function dedupeMessages(messages: PersistedMessage[]): PersistedMessage[] {
  const seenIds = new Set<string>()
  const deduped: PersistedMessage[] = []

  for (const message of messages) {
    if (seenIds.has(message.id)) {
      continue
    }

    seenIds.add(message.id)
    deduped.push(message)
  }

  return deduped
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError'
}
