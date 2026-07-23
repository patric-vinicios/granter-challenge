import { computed, onUnmounted, ref, watch, type Ref } from 'vue'

import { createRealtimeSocket, type RealtimeChannel, type RealtimeSocket, type RealtimeSocketFactory } from '@/shared/realtime/socket'

import {
  decodeConversationUpdated,
  decodeMembershipRevoked,
  decodeMessageAck,
  decodeMessageSendError,
  decodePersistedMessage,
} from './messaging.contracts'
import { useMessagingStore } from './messaging.store'

interface UseRealtimeMessagingOptions {
  token: Ref<string | null>
  userId: Ref<string | null>
  selectedConversationId: Ref<string | null>
  socketFactory?: RealtimeSocketFactory
}

export function useRealtimeMessaging({
  token,
  userId,
  selectedConversationId,
  socketFactory = createRealtimeSocket,
}: UseRealtimeMessagingOptions) {
  const store = useMessagingStore()
  const socket = ref<RealtimeSocket | null>(null)
  const userChannel = ref<RealtimeChannel | null>(null)
  const conversationChannel = ref<RealtimeChannel | null>(null)
  const joinedConversationId = ref<string | null>(null)
  const status = ref<'idle' | 'connecting' | 'connected' | 'error'>('idle')
  const error = ref<string | null>(null)

  const canSend = computed(() => status.value === 'connected' && conversationChannel.value !== null)

  watch(
    [token, userId],
    ([currentToken, currentUserId], _previous, onCleanup) => {
      disconnect()

      if (!currentToken || !currentUserId) {
        status.value = 'idle'
        return
      }

      const nextSocket = socketFactory(currentToken)
      socket.value = nextSocket
      status.value = 'connecting'
      nextSocket.connect()
      userChannel.value = nextSocket.channel(`user:${currentUserId}`)
      userChannel.value.on('conversation:updated', handleConversationUpdated)
      userChannel.value.join().receive('ok', () => {
        status.value = 'connected'
      }).receive('error', () => {
        status.value = 'error'
        error.value = 'Não foi possível receber atualizações em tempo real.'
      })

      joinConversation(selectedConversationId.value)
      onCleanup(disconnect)
    },
    { immediate: true },
  )

  watch(selectedConversationId, (conversationId) => {
    joinConversation(conversationId)
  })

  onUnmounted(disconnect)

  function sendMessage(body: string): boolean {
    const channel = conversationChannel.value
    const conversationId = joinedConversationId.value
    const currentUserId = userId.value

    if (!channel || !conversationId || !currentUserId) {
      return false
    }

    const clientRef = `client-${crypto.randomUUID()}`
    store.addOptimisticMessage(conversationId, body, clientRef)
    channel
      .push('new_message', { body, client_ref: clientRef })
      .receive('ok', (payload) => {
        const ack = decodeMessageAck(payload)
        store.confirmMessage(ack.message, currentUserId, ack.clientRef)
      })
      .receive('error', (payload) => {
        const sendError = decodeMessageSendError(payload)
        store.failMessage(sendError.clientRef, sendError)
        error.value = messageErrorText(sendError.reason)
      })

    return true
  }

  function joinConversation(conversationId: string | null): void {
    leaveConversation()

    if (!socket.value || !conversationId) {
      return
    }

    const currentUserId = userId.value
    const channel = socket.value.channel(`conversation:${conversationId}`)
    conversationChannel.value = channel
    joinedConversationId.value = conversationId
    channel.on('message:new', (payload) => {
      if (currentUserId) {
        store.receiveMessage(decodePersistedMessage(payload), currentUserId)
      }
    })
    channel.on('conversation:membership_revoked', (payload) => {
      const revoked = decodeMembershipRevoked(payload)
      store.revokeConversation(revoked.conversationId)
      error.value = 'Voce saiu desta conversa.'
      leaveConversation()
    })
    channel.join().receive('error', () => {
      status.value = 'error'
      error.value = 'Não foi possível entrar nesta conversa.'
      leaveConversation()
    })
  }

  function leaveConversation(): void {
    conversationChannel.value?.leave()
    conversationChannel.value = null
    joinedConversationId.value = null
  }

  function disconnect(): void {
    leaveConversation()
    userChannel.value?.leave()
    userChannel.value = null
    socket.value?.disconnect()
    socket.value = null
  }

  function handleConversationUpdated(payload: unknown): void {
    const currentUserId = userId.value

    if (currentUserId) {
      store.applyConversationUpdate(decodeConversationUpdated(payload), currentUserId)
    }
  }

  return {
    canSend,
    error,
    sendMessage,
    status,
  }
}

function messageErrorText(reason: string): string {
  if (reason === 'validation_error') {
    return 'Confira a mensagem antes de enviar.'
  }

  if (reason === 'rate_limited') {
    return 'Aguarde alguns instantes antes de enviar novamente.'
  }

  if (reason === 'unauthorized') {
    return 'Voce saiu desta conversa.'
  }

  return 'Não foi possível enviar a mensagem.'
}
