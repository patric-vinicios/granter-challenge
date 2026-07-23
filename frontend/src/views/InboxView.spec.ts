import { screen, waitFor, within } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useAuthStore } from '@/stores/auth.store'
import { renderWithApp } from '@/test/render'

import InboxView from './InboxView.vue'

const sockets: FakeSocket[] = []

vi.mock('@/shared/realtime/socket', () => ({
  createRealtimeSocket: (token: string) => {
    const socket = new FakeSocket(token)
    sockets.push(socket)
    return socket
  },
}))

const routes = [
  {
    path: '/',
    component: { template: '<div>Login</div>' },
  },
  {
    path: '/inbox',
    component: InboxView,
  },
]

async function renderInbox() {
  return renderWithApp(InboxView, { routes, initialRoute: '/inbox' })
}

describe('InboxView', () => {
  beforeEach(() => {
    sockets.length = 0
  })

  it('shows the default conversation and switches to another conversation', async () => {
    const user = userEvent.setup()

    await renderInbox()

    expect(screen.getByText('visto por ultimo ha 5 min')).toBeTruthy()
    expect(screen.getByText('Perfeito, fico no aguardo entao')).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /time de produto/i }))

    expect(screen.getByText('5 membros · Voce, Rafael, Ana, +2')).toBeTruthy()
    expect(screen.getByText('Bom dia pessoal! Subi a build de staging pra validacao')).toBeTruthy()
    expect(screen.getAllByText('Rafael Alves')).toHaveLength(2)
  })

  it('opens contacts and reports add-contact success and error states', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        contacts: [
          contactResponse('contact-rafael', 'user-rafael', 'rafaelalves', 'Rafael Alves'),
          contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
        ],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))

    expect(screen.getByText('Contatos')).toBeTruthy()
    expect(await screen.findByText('@rafaelalves')).toBeTruthy()
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )

    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const dialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    const usernameInput = within(dialog).getByLabelText(/usuario/i)

    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, {
        contact: contactResponse('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva'),
      }),
    )

    await user.type(usernameInput, '@anabeatriz')
    await user.click(within(dialog).getByRole('button', { name: /adicionar/i }))

    expect(await within(dialog).findByText(/contato adicionado/i)).toBeTruthy()
    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ username: '@anabeatriz' }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
          'Content-Type': 'application/json',
        }),
      }),
    )
    expect(screen.getByText('@carlos')).toBeTruthy()

    await user.click(within(dialog).getByRole('button', { name: /voltar/i }))
    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const reopenedDialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    fetchMock.mockResolvedValueOnce(
      jsonResponse(404, {
        errors: {
          code: 'user_not_found',
          detail: 'No user with @fulano123 exists in the system',
        },
      }),
    )

    await user.type(within(reopenedDialog).getByLabelText(/usuario/i), '@fulano123')
    await user.click(within(reopenedDialog).getByRole('button', { name: /adicionar/i }))

    expect(await within(reopenedDialog).findByText(/usuario nao encontrado/i)).toBeTruthy()

    fetchMock.mockResolvedValueOnce(jsonResponse(204, null))
    await user.click(screen.getByRole('button', { name: /remover rafael alves/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/contacts/contact-rafael',
      expect.objectContaining({
        method: 'DELETE',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(screen.queryByText('@rafaelalves')).toBeNull()
  })

  it('opens a private conversation from a contact', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        contacts: [contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz')],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await screen.findByText('@anabeatriz')

    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, {
        conversation: privateConversationResponse('conversation-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
      }),
    )

    await user.click(screen.getByRole('button', { name: /abrir conversa com ana beatriz/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/private',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ user_id: 'user-ana' }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(await screen.findByText('Conversa iniciada')).toBeTruthy()
    expect(screen.getByText('Nenhuma mensagem nesta conversa.')).toBeTruthy()
  })

  it('opens conversation search and clears the draft when sending', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    sockets[0].channelFor('user:user-current').okJoin()
    sockets[0].channelFor('conversation:ana').okJoin()

    await user.click(screen.getByRole('button', { name: /buscar na conversa/i }))

    expect(screen.getByLabelText(/buscar na conversa/i)).toBeTruthy()
    expect(screen.getByText('1 / 1')).toBeTruthy()

    const messageInput = screen.getByLabelText(/^mensagem$/i) as HTMLTextAreaElement

    await user.type(messageInput, 'Mensagem de teste')
    await user.click(screen.getByRole('button', { name: /enviar mensagem/i }))

    expect(messageInput.value).toBe('')
  })

  it('sends over the conversation channel and reconciles the optimistic message from the ack', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
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
      message: messageResponse({
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
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    const socket = sockets[0]
    const conversationChannel = socket.channelFor('conversation:ana')
    const userChannel = socket.channelFor('user:user-current')
    userChannel.okJoin()
    conversationChannel.okJoin()

    conversationChannel.pushServer('message:new', messageResponse({
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

  it('creates and manages a group from contacts', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        contacts: [
          contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
          contactResponse('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva'),
          contactResponse('contact-leticia', 'user-leticia', 'leticia', 'Leticia Moraes'),
        ],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /novo grupo/i }))
    await user.click(screen.getByLabelText(/ana beatriz/i))
    await user.click(screen.getByLabelText(/carlos silva/i))

    fetchMock.mockResolvedValueOnce(jsonResponse(201, { conversation: groupResponse() }))

    await user.clear(screen.getByLabelText(/nome do grupo/i))
    await user.type(screen.getByLabelText(/nome do grupo/i), 'Time de Produto')
    await user.click(screen.getByRole('button', { name: /criar grupo/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/groups',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ name: 'Time de Produto', member_ids: ['user-ana', 'user-carlos'] }),
      }),
    )
    expect(await screen.findByText('Grupo criado')).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /gerenciar grupo/i }))
    expect(screen.getByText('@anabeatriz')).toBeTruthy()

    fetchMock.mockResolvedValueOnce(jsonResponse(204, null))
    await user.click(screen.getByRole('button', { name: /remover ana beatriz/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/group-product/members/user-ana',
      expect.objectContaining({ method: 'DELETE' }),
    )
    expect(screen.queryByRole('button', { name: /remover ana beatriz/i })).toBeNull()

    fetchMock.mockResolvedValueOnce(jsonResponse(200, { conversation: groupResponse({ includeAna: false, includeLeticia: true }) }))
    await user.click(screen.getByRole('button', { name: /leticia moraes/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/group-product/members',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ member_ids: ['user-leticia'] }),
      }),
    )
    expect(await screen.findByText('@leticia')).toBeTruthy()
  })
})

function authenticate(pinia: Awaited<ReturnType<typeof renderInbox>>['pinia']) {
  const auth = useAuthStore(pinia)
  auth.user = {
    id: 'user-current',
    username: 'patric',
    name: 'Patric',
    lastSeenAt: null,
  }
  auth.token = 'jwt-token'
  auth.expiresAt = '2026-07-30T12:00:00Z'
}

function contactResponse(id: string, userId: string, username: string, name: string) {
  return {
    id,
    user: {
      id: userId,
      username,
      name,
      last_seen_at: null,
    },
  }
}

function privateConversationResponse(id: string, userId: string, username: string, name: string) {
  return {
    id,
    type: 'private',
    last_read_at: null,
    counterpart: {
      id: userId,
      username,
      name,
      last_seen_at: null,
    },
  }
}

function groupResponse(options: { includeAna?: boolean; includeLeticia?: boolean } = {}) {
  const includeAna = options.includeAna ?? true
  const members = [
    userResponse('user-current', 'patric', 'Patric'),
    ...(includeAna ? [userResponse('user-ana', 'anabeatriz', 'Ana Beatriz')] : []),
    userResponse('user-carlos', 'carlos', 'Carlos Silva'),
    ...(options.includeLeticia ? [userResponse('user-leticia', 'leticia', 'Leticia Moraes')] : []),
  ]

  return {
    id: 'group-product',
    type: 'group',
    name: 'Time de Produto',
    creator_id: 'user-current',
    member_count: members.length,
    last_read_at: null,
    members,
  }
}

function userResponse(id: string, username: string, name: string) {
  return {
    id,
    username,
    name,
    last_seen_at: null,
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function messageResponse({
  id,
  body,
  senderId,
  senderName,
}: {
  id: string
  body: string
  senderId: string
  senderName: string
}) {
  return {
    id,
    conversation_id: 'ana',
    body,
    inserted_at: '2026-07-23T17:40:00.000000Z',
    sender: {
      id: senderId,
      username: senderName.toLowerCase().replaceAll(' ', ''),
      name: senderName,
      last_seen_at: null,
    },
  }
}

type PushStatus = 'ok' | 'error'

class FakePush {
  private callbacks: Partial<Record<PushStatus, (payload: unknown) => void>> = {}

  receive(status: PushStatus, callback: (payload: unknown) => void): FakePush {
    this.callbacks[status] = callback
    return this
  }

  reply(status: PushStatus, payload: unknown): void {
    this.callbacks[status]?.(payload)
  }
}

class FakeChannel {
  handlers = new Map<string, Array<(payload: unknown) => void>>()
  joinPush = new FakePush()
  lastPush: { event: string; payload: Record<string, unknown>; push: FakePush } | null = null
  leaveCount = 0

  join(): FakePush {
    return this.joinPush
  }

  okJoin(): void {
    this.joinPush.reply('ok', {})
  }

  leave(): void {
    this.leaveCount += 1
  }

  on(event: string, callback: (payload: unknown) => void): number {
    const callbacks = this.handlers.get(event) ?? []
    callbacks.push(callback)
    this.handlers.set(event, callbacks)
    return callbacks.length
  }

  off(): void {}

  push(event: string, payload: Record<string, unknown>): FakePush {
    const push = new FakePush()
    this.lastPush = { event, payload, push }
    return push
  }

  replyLastPush(status: PushStatus, payload: unknown): void {
    this.lastPush?.push.reply(status, payload)
  }

  pushServer(event: string, payload: unknown): void {
    for (const callback of this.handlers.get(event) ?? []) {
      callback(payload)
    }
  }
}

class FakeSocket {
  connected = false
  disconnected = false
  channels = new Map<string, FakeChannel>()
  token: string

  constructor(token: string) {
    this.token = token
  }

  connect(): void {
    this.connected = true
  }

  disconnect(): void {
    this.disconnected = true
  }

  channel(topic: string): FakeChannel {
    const existing = this.channels.get(topic)

    if (existing) {
      return existing
    }

    const channel = new FakeChannel()
    this.channels.set(topic, channel)
    return channel
  }

  channelFor(topic: string): FakeChannel {
    const channel = this.channels.get(topic)

    if (!channel) {
      throw new Error(`Missing channel ${topic}`)
    }

    return channel
  }
}
