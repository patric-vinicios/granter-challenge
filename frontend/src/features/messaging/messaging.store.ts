import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import type { Conversation, Message } from '@/features/conversations/conversations.mock'

import { listMessages } from './messaging.api'
import type { ConversationUpdated, MessageSendError, PersistedMessage } from './messaging.contracts'

interface ConversationHistory {
  messages: PersistedMessage[]
  nextCursor: string | null
  hasMore: boolean
  isLoadingInitial: boolean
  isLoadingOlder: boolean
  didLoadInitial: boolean
  error: string | null
}

interface RealtimeConversationState {
  messages: Message[]
  preview: string
  time: string
  lastActivity: number
  revoked: boolean
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

export const useMessagingStore = defineStore('messaging', () => {
  const conversations = ref<Record<string, RealtimeConversationState>>({})
  const pendingErrors = ref<Record<string, MessageSendError>>({})

  const revokedConversationIds = computed(() =>
    Object.entries(conversations.value)
      .filter(([, state]) => state.revoked)
      .map(([conversationId]) => conversationId),
  )

  function decorate(conversation: Conversation): Conversation {
    const state = conversations.value[conversation.id]

    if (!state) {
      return conversation
    }

    return {
      ...conversation,
      preview: state.preview || conversation.preview,
      time: state.time || conversation.time,
      messages: [...conversation.messages, ...state.messages],
    }
  }

  function sortByActivity(items: Conversation[]): Conversation[] {
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
          side: 'out',
          text: body,
          time: 'Enviando',
          wide: body.length > 42,
        },
      ],
      preview: `Voce: ${body}`,
      time: 'Agora',
      lastActivity: Date.now(),
    })
    delete pendingErrors.value[clientRef]
  }

  function confirmMessage(message: PersistedMessage, currentUserId: string, clientRef: string | null): void {
    const nextMessage = toConversationMessage(message, currentUserId)
    const current = getMessages(message.conversationId)
    const messages =
      clientRef === null
        ? [...current, nextMessage]
        : current.map((item) => (item.time === 'Enviando' && item.text === message.body ? nextMessage : item))

    upsertState(message.conversationId, {
      messages: messages.some((item) => item.time === nextMessage.time && item.text === nextMessage.text)
        ? messages
        : [...messages, nextMessage],
      preview: previewFor(message, currentUserId),
      time: formatMessageTime(message.insertedAt),
      lastActivity: Date.parse(message.insertedAt),
    })

    if (clientRef) {
      delete pendingErrors.value[clientRef]
    }
  }

  function receiveMessage(message: PersistedMessage, currentUserId: string): void {
    const current = getMessages(message.conversationId)

    if (current.some((item) => item.time === formatMessageTime(message.insertedAt) && item.text === message.body)) {
      return
    }

    upsertState(message.conversationId, {
      messages: [...current, toConversationMessage(message, currentUserId)],
      preview: previewFor(message, currentUserId),
      time: formatMessageTime(message.insertedAt),
      lastActivity: Date.parse(message.insertedAt),
    })
  }

  function failMessage(clientRef: string | null, error: MessageSendError): void {
    if (clientRef) {
      pendingErrors.value[clientRef] = error
    }
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

  function revokeConversation(conversationId: string): void {
    upsertState(conversationId, {
      messages: getMessages(conversationId),
      preview: 'Voce saiu desta conversa.',
      time: 'Agora',
      lastActivity: Date.now(),
      revoked: true,
    })
  }

  function reset(): void {
    conversations.value = {}
    pendingErrors.value = {}
  }

  function getMessages(conversationId: string): Message[] {
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
        revoked: next.revoked ?? previous?.revoked ?? false,
      },
    }
  }

  return {
    pendingErrors,
    revokedConversationIds,
    addOptimisticMessage,
    applyConversationUpdate,
    confirmMessage,
    decorate,
    failMessage,
    receiveMessage,
    reset,
    revokeConversation,
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

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError'
}

function toConversationMessage(message: PersistedMessage, currentUserId: string): Message {
  return {
    id: message.id,
    side: message.sender.id === currentUserId ? 'out' : 'in',
    author: message.sender.id === currentUserId ? undefined : message.sender.name,
    text: message.body,
    time: formatMessageTime(message.insertedAt),
    wide: message.body.length > 42,
  }
}

function previewFor(message: PersistedMessage, currentUserId: string): string {
  return `${message.sender.id === currentUserId ? 'Voce: ' : ''}${message.body}`
}

function formatMessageTime(value: string): string {
  const date = new Date(value)

  if (Number.isNaN(date.getTime())) {
    return ''
  }

  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(date)
}
