import { computed, onUnmounted, ref, watch, type Ref } from 'vue'

import { createRealtimeSocket, type RealtimeChannel, type RealtimeSocket, type RealtimeSocketFactory } from '@/shared/realtime/socket'
import type { ConversationUpdated } from '@/types/realtime'

import {
  decodeConversationUpdated,
  decodeMembershipRevoked,
  decodeMessageAck,
  decodeMessageSendError,
  decodePersistedMessage,
} from './messaging.contracts'
import { useMessagesStore, useMessagingStore } from './messaging.store'

interface UseRealtimeMessagingOptions {
  token: Ref<string | null>
  userId: Ref<string | null>
  selectedConversationId: Ref<string | null>
  socketFactory?: RealtimeSocketFactory
  onPresenceState?: (payload: unknown) => void
  onPresenceDiff?: (payload: unknown) => void
  onConversationUpdated?: (update: ConversationUpdated) => void
  onMembershipRevoked?: (conversationId: string) => void
  onReconnect?: () => void
}

export function useRealtimeMessaging({
  token,
  userId,
  selectedConversationId,
  socketFactory = createRealtimeSocket,
  onPresenceState,
  onPresenceDiff,
  onConversationUpdated,
  onMembershipRevoked,
  onReconnect,
}: UseRealtimeMessagingOptions) {
  const store = useMessagingStore()
  const messagesStore = useMessagesStore()
  const socket = ref<RealtimeSocket | null>(null)
  const userChannel = ref<RealtimeChannel | null>(null)
  const userChannelHandlers = ref<Array<{ event: string; ref: number }>>([])
  const conversationChannel = ref<RealtimeChannel | null>(null)
  const conversationChannelHandlers = ref<Array<{ event: string; ref: number }>>([])
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
      error.value = null
      let didOpen = false
      const socketStateRefs = [
        nextSocket.onOpen(() => {
          status.value = 'connected'
          error.value = null

          if (didOpen) {
            onReconnect?.()
          }

          didOpen = true
        }),
        nextSocket.onClose(() => {
          status.value = 'error'
          error.value = 'Não foi possível manter a conexão em tempo real.'
        }),
        nextSocket.onError(() => {
          status.value = 'error'
          error.value = 'Não foi possível manter a conexão em tempo real.'
        }),
      ]
      nextSocket.connect()
      userChannel.value = nextSocket.channel(`user:${currentUserId}`)
      userChannelHandlers.value = [
        {
          event: 'conversation:updated',
          ref: userChannel.value.on('conversation:updated', handleConversationUpdated),
        },
      ]
      userChannel.value.join().receive('ok', () => {
        status.value = 'connected'
        error.value = null
      }).receive('error', () => {
        status.value = 'error'
        error.value = 'Não foi possível receber atualizações em tempo real.'
      })

      joinConversation(selectedConversationId.value)
      onCleanup(() => {
        nextSocket.off(socketStateRefs)
        disconnect()
      })
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
    conversationChannelHandlers.value = [
      {
        event: 'message:new',
        ref: channel.on('message:new', (payload) => {
          if (currentUserId) {
            store.receiveMessage(decodePersistedMessage(payload), currentUserId)
          }
        }),
      },
      {
        event: 'conversation:membership_revoked',
        ref: channel.on('conversation:membership_revoked', (payload) => {
          const revoked = decodeMembershipRevoked(payload)
          store.revokeConversation(revoked.conversationId)
          onMembershipRevoked?.(revoked.conversationId)
          error.value = 'Voce saiu desta conversa.'
          leaveConversation()
        }),
      },
    ]

    if (onPresenceState) {
      conversationChannelHandlers.value = [
        ...conversationChannelHandlers.value,
        {
          event: 'presence:state',
          ref: channel.on('presence:state', onPresenceState),
        },
      ]
    }

    if (onPresenceDiff) {
      conversationChannelHandlers.value = [
        ...conversationChannelHandlers.value,
        {
          event: 'presence:diff',
          ref: channel.on('presence:diff', onPresenceDiff),
        },
      ]
    }

    channel
      .join()
      .receive('ok', () => {
        status.value = 'connected'
        error.value = null
      })
      .receive('error', () => {
        status.value = 'error'
        error.value = 'Não foi possível entrar nesta conversa.'
        leaveConversation()
      })
  }

  function leaveConversation(): void {
    const channel = conversationChannel.value

    if (channel) {
      for (const handler of conversationChannelHandlers.value) {
        channel.off(handler.event, handler.ref)
      }

      channel.leave()
    }

    conversationChannelHandlers.value = []
    conversationChannel.value = null
    joinedConversationId.value = null
  }

  function disconnect(): void {
    leaveConversation()
    const channel = userChannel.value

    if (channel) {
      for (const handler of userChannelHandlers.value) {
        channel.off(handler.event, handler.ref)
      }

      channel.leave()
    }

    userChannelHandlers.value = []
    userChannel.value = null
    socket.value?.disconnect()
    socket.value = null
  }

  function handleConversationUpdated(payload: unknown): void {
    const currentUserId = userId.value
    const update = decodeConversationUpdated(payload)

    if (currentUserId) {
      store.applyConversationUpdate(update, currentUserId)
    }

    onConversationUpdated?.(update)

    if (token.value && update.conversationId === selectedConversationId.value) {
      void messagesStore.loadInitial(update.conversationId, token.value, undefined, { force: true, silent: true })
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
