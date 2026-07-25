import { screen, waitFor, within } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, it, expect, vi } from 'vitest'

import {
  authenticate,
  defaultAnaInboxSummary,
  historyMessageResponse,
  inboxSummaryResponse,
  mockAuthenticatedFetch,
  realtimeMessageResponse,
  renderInbox,
  resetInboxHarness,
  sockets,
} from './inbox/inboxTestHarness'

describe('Inbox realtime and presence', () => {
  beforeEach(resetInboxHarness)

  it('sends over the conversation channel and reconciles the optimistic message from the ack', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    vi.stubGlobal('fetch', mockAuthenticatedFetch({ conversations: [defaultAnaInboxSummary()] }))
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    await screen.findAllByText('Ana Beatriz')
    const socket = sockets[0]
    socket.channelFor('user:user-current').okJoin()
    const conversationChannel = socket.channelFor('conversation:ana')
    conversationChannel.okJoin()

    const messageInput = screen.getByLabelText(/^mensagem$/i) as HTMLTextAreaElement

    await user.type(messageInput, 'Mensagem de teste')
    await user.click(screen.getByRole('button', { name: /enviar mensagem/i }))

    expect(conversationChannel.lastPush).toMatchObject({
      event: 'new_message',
      payload: {
        body: 'Mensagem de teste',
      },
    })
    expect(conversationChannel.lastPush?.payload.client_ref).toEqual(expect.stringMatching(/^client-/))
    expect(screen.getByText('Mensagem de teste')).toBeTruthy()
    expect(screen.getByText('Enviando')).toBeTruthy()

    conversationChannel.replyLastPush('ok', {
      message: realtimeMessageResponse({
        id: 'message-1',
        body: 'Mensagem de teste',
        senderId: 'user-current',
        senderName: 'Patric',
      }),
      client_ref: conversationChannel.lastPush?.payload.client_ref,
    })

    await waitFor(() => expect(screen.queryByText('Enviando')).toBeNull())
    expect(screen.getAllByText('14:40').length).toBeGreaterThanOrEqual(1)
    expect(messageInput.value).toBe('')
  })

  it('applies incoming conversation messages, user updates, and membership revocation events', async () => {
    const { pinia } = await renderInbox()
    vi.stubGlobal('fetch', mockAuthenticatedFetch({ conversations: [defaultAnaInboxSummary()] }))
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    await screen.findAllByText('Ana Beatriz')
    const socket = sockets[0]
    const conversationChannel = socket.channelFor('conversation:ana')
    const userChannel = socket.channelFor('user:user-current')
    userChannel.okJoin()
    conversationChannel.okJoin()

    conversationChannel.pushServer('message:new', realtimeMessageResponse({
      id: 'message-2',
      body: 'Cheguei por socket',
      senderId: 'user-ana',
      senderName: 'Ana Beatriz',
    }))

    await waitFor(() => expect(screen.getAllByText('Cheguei por socket').length).toBeGreaterThanOrEqual(1))
    expect(screen.getAllByText('Ana Beatriz').length).toBeGreaterThanOrEqual(1)

    userChannel.pushServer('conversation:updated', {
      conversation_id: 'ana',
      last_message: {
        preview: 'Cheguei por socket',
        sender_id: 'user-ana',
        inserted_at: '2026-07-23T17:40:00.000000Z',
      },
      unread: true,
    })

    expect(screen.getAllByText('Cheguei por socket').length).toBeGreaterThanOrEqual(1)

    conversationChannel.pushServer('conversation:membership_revoked', {
      conversation_id: 'ana',
    })

    expect((await screen.findAllByText('Voce saiu desta conversa.')).length).toBeGreaterThanOrEqual(1)
    expect(conversationChannel.leaveCount).toBe(1)
  })

  it('acknowledges an incoming update as read when its conversation is already visible', async () => {
    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({ conversations: [defaultAnaInboxSummary()] })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    await screen.findAllByText('Ana Beatriz')
    const userChannel = sockets[0].channelFor('user:user-current')
    userChannel.okJoin()

    userChannel.pushServer('conversation:updated', {
      conversation_id: 'ana',
      last_message: {
        preview: 'Mensagem recebida com a conversa aberta',
        sender_id: 'user-ana',
        inserted_at: '2026-07-24T18:00:00Z',
      },
      unread: true,
    })

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        'http://localhost:4000/api/conversations/ana/read',
        expect.objectContaining({ method: 'POST' }),
      ),
    )
    expect(screen.queryByLabelText('1 mensagens nao lidas')).toBeNull()
  })

  it('reloads cached history when a message arrives while another conversation is visible', async () => {
    const user = userEvent.setup()
    const oldMessage = historyMessageResponse(
      'message-old',
      'Mensagem anterior',
      'user-ana',
      'Ana Beatriz',
      '2026-07-24T17:00:00Z',
    )
    const newMessage = historyMessageResponse(
      'message-new',
      'Mensagem recebida fora da conversa',
      'user-ana',
      'Ana Beatriz',
      '2026-07-24T18:00:00Z',
    )
    const fetchMock = mockAuthenticatedFetch({
      conversations: [
        defaultAnaInboxSummary(),
        inboxSummaryResponse({
          id: 'group-product',
          type: 'group',
          title: 'Time de Produto',
          senderId: 'user-current',
          body: 'Conversa alternativa',
          unreadCount: 0,
        }),
      ],
      historyResponses: [[oldMessage], [], [oldMessage, newMessage]],
    })
    const { pinia } = await renderInbox()
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    expect(await screen.findByText('Mensagem anterior')).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /time de produto/i }))
    await waitFor(() =>
      expect(sockets[0].channels.has('conversation:group-product')).toBe(true),
    )

    sockets[0].channelFor('user:user-current').pushServer('conversation:updated', {
      conversation_id: 'ana',
      last_message: {
        preview: 'Mensagem recebida fora da conversa',
        sender_id: 'user-ana',
        inserted_at: '2026-07-24T18:00:00Z',
      },
      unread: true,
    })

    await user.click(screen.getByRole('button', { name: /ana beatriz/i }))

    expect(
      await within(screen.getByRole('log', { name: /mensagens da conversa/i })).findByText(
        'Mensagem recebida fora da conversa',
      ),
    ).toBeTruthy()
    expect(requestCount(fetchMock, '/api/conversations/ana/messages?limit=30')).toBe(2)
  })

  it('clears the realtime connection error after the socket reconnects', async () => {
    const { pinia } = await renderInbox()
    vi.stubGlobal('fetch', mockAuthenticatedFetch({ conversations: [defaultAnaInboxSummary()] }))
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    await screen.findAllByText('Ana Beatriz')
    const socket = sockets[0]
    socket.channelFor('user:user-current').okJoin()

    socket.emitClose()

    expect(await screen.findByText('Não foi possível manter a conexão em tempo real.')).toBeTruthy()

    socket.emitOpen()

    await waitFor(() =>
      expect(screen.queryByText('Não foi possível manter a conexão em tempo real.')).toBeNull(),
    )
  })

  it('refreshes inbox and history after reconnecting without losing the selection', async () => {
    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({ conversations: [defaultAnaInboxSummary()] })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    await screen.findAllByText('Ana Beatriz')
    const socket = sockets[0]
    socket.channelFor('user:user-current').okJoin()
    socket.emitOpen()
    const inboxCallsBefore = requestCount(fetchMock, '/api/conversations')
    const historyCallsBefore = requestCount(
      fetchMock,
      '/api/conversations/ana/messages?limit=30',
    )

    socket.emitClose()
    socket.emitOpen()

    await waitFor(() =>
      expect(requestCount(fetchMock, '/api/conversations')).toBeGreaterThan(inboxCallsBefore),
    )
    await waitFor(() =>
      expect(
        requestCount(fetchMock, '/api/conversations/ana/messages?limit=30'),
      ).toBeGreaterThan(historyCallsBefore),
    )
    expect(screen.getAllByText('Ana Beatriz').length).toBeGreaterThanOrEqual(1)
  })

  it('renders presence from the authenticated conversation before realtime updates arrive', async () => {
    const { pinia } = await renderInbox()
    vi.stubGlobal(
      'fetch',
      mockAuthenticatedFetch({
        conversations: [
          inboxSummaryResponse({
            id: 'ana',
            title: 'Ana Beatriz',
            senderId: 'user-ana',
            body: 'Perfeito, fico no aguardo entao',
            unreadCount: 0,
            online: true,
          }),
        ],
      }),
    )

    authenticate(pinia)

    expect(await screen.findByText('online')).toBeTruthy()
  })

  it('renders presence from conversation data and updates it from channel events', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    vi.stubGlobal(
      'fetch',
      mockAuthenticatedFetch({
        conversations: [
          inboxSummaryResponse({
            id: 'ana',
            title: 'Ana Beatriz',
            senderId: 'user-ana',
            body: 'Perfeito, fico no aguardo entao',
            unreadCount: 0,
            online: false,
            lastSeenAt: null,
          }),
          inboxSummaryResponse({
            id: 'group-product',
            type: 'group',
            title: 'Time de Produto',
            senderId: 'user-rafael',
            body: 'Bom dia pessoal! Subi a build de staging pra validacao',
            unreadCount: 0,
            memberCount: 5,
          }),
        ],
      }),
    )
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    await screen.findAllByText('Ana Beatriz')

    const socket = sockets[0]
    const conversationChannel = socket.channelFor('conversation:ana')

    expect(await screen.findByText('offline')).toBeTruthy()

    conversationChannel.pushServer('presence:state', {
      'user-ana': {
        metas: [{ online_at: '2026-07-23T17:44:00.000Z' }],
      },
    })

    expect(await screen.findByText('online')).toBeTruthy()

    conversationChannel.pushServer('presence:diff', {
      joins: {},
      leaves: {
        'user-ana': {
          metas: [{}],
        },
      },
    })

    expect(await screen.findByText('visto por ultimo agora')).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /time de produto/i }))

    expect(conversationChannel.offEvents).toEqual(
      expect.arrayContaining(['message:new', 'conversation:membership_revoked', 'presence:state', 'presence:diff']),
    )
    expect(conversationChannel.leaveCount).toBe(1)
  })
})

function requestCount(fetchMock: ReturnType<typeof vi.fn>, path: string): number {
  return fetchMock.mock.calls.filter(([input]) => String(input).endsWith(path)).length
}
