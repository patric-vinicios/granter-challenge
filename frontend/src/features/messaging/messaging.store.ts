import { defineStore } from 'pinia'
import { ref } from 'vue'

import { formatMessageTime } from '@/shared/date/formatMessageTime'
import { toChatMessage } from '@/shared/chat/toChatMessage'
import type { ChatConversation, ChatMessage } from '@/types/chat'

import { listMessages } from './messaging.api'
import type { ConversationUpdated, PersistedMessage } from './messaging.contracts'
import {
  createEmptyConversationHistory,
  type ConversationHistory,
} from './messaging.history'

interface RealtimeConversationState {
  messages: ChatMessage[]
  preview: string
  time: string
  lastActivity: number
}

export const useMessagesStore = defineStore('messages', () => {
  const histories = ref<Record<string, ConversationHistory>>({})
  const pendingRefreshIds = ref<Set<string>>(new Set())

  async function loadInitial(
    conversationId: string,
    token: string,
    signal?: AbortSignal,
    options: { force?: boolean; silent?: boolean } = {},
  ): Promise<void> {
    const current = ensureHistory(conversationId)

    if (current.isLoadingInitial) {
      if (options.force) {
        pendingRefreshIds.value = new Set(pendingRefreshIds.value).add(conversationId)
      }

      return
    }

    if (current.didLoadInitial && !options.force) {
      return
    }

    setHistory(conversationId, {
      ...current,
      isLoadingInitial: !options.silent,
      error: null,
    })

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

      if (pendingRefreshIds.value.has(conversationId)) {
        const nextPendingRefreshIds = new Set(pendingRefreshIds.value)
        nextPendingRefreshIds.delete(conversationId)
        pendingRefreshIds.value = nextPendingRefreshIds
        void loadInitial(conversationId, token, signal, { force: true, silent: true })
      }
    } catch (error) {
      if (pendingRefreshIds.value.has(conversationId)) {
        const nextPendingRefreshIds = new Set(pendingRefreshIds.value)
        nextPendingRefreshIds.delete(conversationId)
        pendingRefreshIds.value = nextPendingRefreshIds
      }

      if (isAbortError(error)) {
        setHistory(conversationId, {
          ...ensureHistory(conversationId),
          isLoadingInitial: false,
          didLoadInitial: false,
          error: null,
        })
        return
      }

      if (options.silent) {
        setHistory(conversationId, {
          ...ensureHistory(conversationId),
          isLoadingInitial: false,
          error: null,
        })
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
    pendingRefreshIds.value = new Set()
  }

  function invalidate(conversationId: string): void {
    const current = histories.value[conversationId]

    if (!current) {
      return
    }

    if (current.isLoadingInitial) {
      pendingRefreshIds.value = new Set(pendingRefreshIds.value).add(conversationId)
      return
    }

    setHistory(conversationId, {
      ...current,
      didLoadInitial: false,
    })
  }

  function removeConversation(conversationId: string): void {
    const nextHistories = { ...histories.value }
    delete nextHistories[conversationId]
    histories.value = nextHistories

    const nextPendingRefreshIds = new Set(pendingRefreshIds.value)
    nextPendingRefreshIds.delete(conversationId)
    pendingRefreshIds.value = nextPendingRefreshIds
  }

  function ensureHistory(conversationId: string): ConversationHistory {
    return histories.value[conversationId] ?? createEmptyConversationHistory()
  }

  function setHistory(conversationId: string, history: ConversationHistory): void {
    histories.value = {
      ...histories.value,
      [conversationId]: history,
    }
  }

  return {
    histories,
    pendingRefreshIds,
    invalidate,
    loadInitial,
    loadOlder,
    removeConversation,
    reset,
  }
})

export const useMessagingStore = defineStore('messaging', () => {
  const conversations = ref<Record<string, RealtimeConversationState>>({})

  function decorate(conversation: ChatConversation): ChatConversation {
    const state = conversations.value[conversation.id]

    if (!state) {
      return conversation
    }

    return {
      ...conversation,
      preview: state.preview || conversation.preview,
      time: state.time || conversation.time,
      messages: mergeConversationMessages(conversation.messages, state.messages),
    }
  }

  function sortByActivity(items: ChatConversation[]): ChatConversation[] {
    return [...items].sort((a, b) => {
      const bActivity = conversations.value[b.id]?.lastActivity ?? 0
      const aActivity = conversations.value[a.id]?.lastActivity ?? 0

      return bActivity - aActivity
    })
  }

  function addOptimisticMessage(conversationId: string, body: string, clientRef: string): void {
    upsertState(conversationId, {
      messages: [
        ...getMessages(conversationId),
        {
          id: clientRef,
          clientRef,
          side: 'out',
          text: body,
          time: 'Enviando',
        },
      ],
      preview: `Voce: ${body}`,
      time: 'Agora',
      lastActivity: Date.now(),
    })
  }

  function confirmMessage(message: PersistedMessage, currentUserId: string, clientRef: string | null): void {
    const nextMessage = toChatMessage(message, currentUserId)
    const current = getMessages(message.conversationId)
    const wasReconciled = clientRef !== null && current.some((item) => item.clientRef === clientRef)
    const messages = wasReconciled
      ? current.map((item) => (item.clientRef === clientRef ? nextMessage : item))
      : current

    upsertState(message.conversationId, {
      messages: messages.some((item) => item.id === nextMessage.id) ? messages : [...messages, nextMessage],
      preview: previewFor(message, currentUserId),
      time: formatMessageTime(message.insertedAt),
      lastActivity: Date.parse(message.insertedAt),
    })

  }

  function receiveMessage(message: PersistedMessage, currentUserId: string): void {
    const current = getMessages(message.conversationId)

    if (current.some((item) => item.id === message.id)) {
      return
    }

    upsertState(message.conversationId, {
      messages: [...current, toChatMessage(message, currentUserId)],
      preview: previewFor(message, currentUserId),
      time: formatMessageTime(message.insertedAt),
      lastActivity: Date.parse(message.insertedAt),
    })
  }

  function applyConversationUpdate(update: ConversationUpdated, currentUserId: string): void {
    const prefix = update.lastMessage.senderId === currentUserId ? 'Voce: ' : ''

    upsertState(update.conversationId, {
      messages: getMessages(update.conversationId),
      preview: `${prefix}${update.lastMessage.preview}`,
      time: formatMessageTime(update.lastMessage.insertedAt),
      lastActivity: Date.parse(update.lastMessage.insertedAt),
    })
  }

  function reset(): void {
    conversations.value = {}
  }

  function removeConversation(conversationId: string): void {
    const nextConversations = { ...conversations.value }
    delete nextConversations[conversationId]
    conversations.value = nextConversations
  }

  function getMessages(conversationId: string): ChatMessage[] {
    return conversations.value[conversationId]?.messages ?? []
  }

  function upsertState(conversationId: string, next: Partial<RealtimeConversationState> & Pick<RealtimeConversationState, 'messages'>): void {
    const previous = conversations.value[conversationId]

    conversations.value = {
      ...conversations.value,
      [conversationId]: {
        messages: next.messages,
        preview: next.preview ?? previous?.preview ?? '',
        time: next.time ?? previous?.time ?? '',
        lastActivity: next.lastActivity ?? previous?.lastActivity ?? 0,
      },
    }
  }

  return {
    conversations,
    addOptimisticMessage,
    applyConversationUpdate,
    confirmMessage,
    decorate,
    receiveMessage,
    removeConversation,
    reset,
    sortByActivity,
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

function mergeConversationMessages(history: ChatMessage[], realtime: ChatMessage[]): ChatMessage[] {
  const seenIds = new Set<string>()

  return [...history, ...realtime].filter((message) => {
    if (!message.id) {
      return true
    }

    if (seenIds.has(message.id)) {
      return false
    }

    seenIds.add(message.id)
    return true
  })
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError'
}

function previewFor(message: PersistedMessage, currentUserId: string): string {
  return `${message.sender.id === currentUserId ? 'Voce: ' : ''}${message.body}`
}
