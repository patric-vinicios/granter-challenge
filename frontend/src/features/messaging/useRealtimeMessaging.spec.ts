import { createPinia } from 'pinia'
import { nextTick, shallowRef } from 'vue'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { withSetup } from '@/test/composable'
import { FakeSocket } from '@/test/realtime'

import { useMessagingStore } from './messaging.store'
import { useRealtimeMessaging } from './useRealtimeMessaging'

describe('useRealtimeMessaging', () => {
  let unmount: (() => void) | undefined

  afterEach(() => {
    unmount?.()
    unmount = undefined
  })

  it('connects the personal and selected-conversation channels', () => {
    const context = setupRealtime()
    unmount = context.unmount

    expect(context.socket.connected).toBe(true)
    expect(context.socket.channels.has('user:user-current')).toBe(true)
    expect(context.socket.channels.has('conversation:conversation-1')).toBe(true)
    expect(context.result.status.value).toBe('connecting')
    expect(context.result.canSend.value).toBe(false)

    context.socket.channelFor('conversation:conversation-1').okJoin()

    expect(context.result.status.value).toBe('connected')
    expect(context.result.canSend.value).toBe(true)
  })

  it('leaves the previous channel and removes its handlers when selection changes', async () => {
    const context = setupRealtime()
    unmount = context.unmount
    const previousChannel = context.socket.channelFor('conversation:conversation-1')

    context.selectedConversationId.value = 'conversation-2'
    await nextTick()

    expect(previousChannel.offEvents).toEqual([
      'message:new',
      'conversation:membership_revoked',
    ])
    expect(previousChannel.leaveCount).toBe(1)
    expect(context.socket.channels.has('conversation:conversation-2')).toBe(true)
  })

  it('disconnects the socket and removes every handler on unmount', () => {
    const context = setupRealtime()
    const userChannel = context.socket.channelFor('user:user-current')
    const conversationChannel = context.socket.channelFor('conversation:conversation-1')

    context.unmount()

    expect(context.socket.disconnected).toBe(true)
    expect(context.socket.stateCallbackCount).toBe(0)
    expect(context.socket.offRefs).toHaveLength(3)
    expect(userChannel.offEvents).toEqual(['conversation:updated'])
    expect(userChannel.leaveCount).toBe(1)
    expect(conversationChannel.offEvents).toEqual([
      'message:new',
      'conversation:membership_revoked',
    ])
    expect(conversationChannel.leaveCount).toBe(1)
  })

  it('replaces the socket cleanly when authentication changes', async () => {
    const context = setupRealtime()
    unmount = context.unmount

    context.token.value = 'replacement-token'
    await nextTick()

    expect(context.socket.disconnected).toBe(true)
    expect(context.socket.stateCallbackCount).toBe(0)
    expect(context.sockets).toHaveLength(2)
    expect(context.sockets[1]?.token).toBe('replacement-token')
    expect(context.sockets[1]?.connected).toBe(true)
  })

  it('reports personal-topic and conversation-topic join failures', () => {
    const personalFailure = setupRealtime()
    unmount = personalFailure.unmount

    personalFailure.socket.channelFor('user:user-current').replyJoin('error')
    expect(personalFailure.result.status.value).toBe('error')
    expect(personalFailure.result.error.value).toBe(
      'Não foi possível receber atualizações em tempo real.',
    )

    personalFailure.socket.channelFor('conversation:conversation-1').replyJoin('error')
    expect(personalFailure.result.error.value).toBe(
      'Não foi possível entrar nesta conversa.',
    )
    expect(personalFailure.result.canSend.value).toBe(false)
  })

  it.each([
    ['validation_error', 'Confira a mensagem antes de enviar.'],
    ['rate_limited', 'Aguarde alguns instantes antes de enviar novamente.'],
    ['unauthorized', 'Voce saiu desta conversa.'],
    ['unknown_event', 'Não foi possível enviar a mensagem.'],
  ] as const)('maps %s send failures to actionable feedback', (reason, expectedMessage) => {
    const context = setupRealtime()
    unmount = context.unmount
    const channel = context.socket.channelFor('conversation:conversation-1')
    channel.okJoin()

    expect(context.result.sendMessage('Mensagem de teste')).toBe(true)
    const clientRef = channel.lastPush?.payload.client_ref
    expect(clientRef).toEqual(expect.stringMatching(/^client-/))

    channel.replyLastPush('error', {
      reason,
      client_ref: clientRef,
    })

    expect(context.result.error.value).toBe(expectedMessage)
    expect(context.messagingStore.pendingErrors[String(clientRef)]).toMatchObject({
      reason,
      clientRef,
    })
  })

  it('calls reconnect recovery only after a connection has opened before', () => {
    const onReconnect = vi.fn()
    const context = setupRealtime({ onReconnect })
    unmount = context.unmount

    context.socket.emitOpen()
    expect(onReconnect).not.toHaveBeenCalled()

    context.socket.emitClose()
    expect(context.result.status.value).toBe('error')

    context.socket.emitOpen()
    expect(onReconnect).toHaveBeenCalledOnce()
    expect(context.result.status.value).toBe('connected')
    expect(context.result.error.value).toBeNull()
  })

  it('stays idle and refuses sends when authentication is absent', () => {
    const context = setupRealtime({ token: null, userId: null })
    unmount = context.unmount

    expect(context.sockets).toHaveLength(0)
    expect(context.result.status.value).toBe('idle')
    expect(context.result.canSend.value).toBe(false)
    expect(context.result.sendMessage('Mensagem')).toBe(false)
  })
})

function setupRealtime(
  options: {
    token?: string | null
    userId?: string | null
    onReconnect?: () => void
  } = {},
) {
  const pinia = createPinia()
  const token = shallowRef<string | null>(options.token === undefined ? 'jwt-token' : options.token)
  const userId = shallowRef<string | null>(
    options.userId === undefined ? 'user-current' : options.userId,
  )
  const selectedConversationId = shallowRef<string | null>('conversation-1')
  const sockets: FakeSocket[] = []
  const setup = withSetup(
    () =>
      useRealtimeMessaging({
        token,
        userId,
        selectedConversationId,
        socketFactory: (currentToken) => {
          const socket = new FakeSocket(currentToken)
          sockets.push(socket)
          return socket
        },
        onReconnect: options.onReconnect,
      }),
    { pinia },
  )

  const socket = sockets[0]

  if (!socket && token.value && userId.value) {
    throw new Error('Expected the realtime composable to create a socket')
  }

  return {
    ...setup,
    messagingStore: useMessagingStore(pinia),
    selectedConversationId,
    socket: socket as FakeSocket,
    sockets,
    token,
  }
}
