import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import type { Conversation, Message } from '@/features/conversations/conversations.mock'

import type { ConversationUpdated, MessageSendError, PersistedMessage } from './messaging.contracts'

interface RealtimeConversationState {
  messages: Message[]
  preview: string
  time: string
  lastActivity: number
  revoked: boolean
}

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
      messages: messages.some((item) => item.time === nextMessage.time && item.text === nextMessage.text) ? messages : [...messages, nextMessage],
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

function toConversationMessage(message: PersistedMessage, currentUserId: string): Message {
  return {
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
