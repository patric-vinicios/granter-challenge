import { fireEvent, screen, waitFor, within } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

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

  afterEach(() => {
    vi.useRealTimers()
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
    const fetchMock = mockAuthenticatedFetch({
      contacts: [
        contactResponse('contact-rafael', 'user-rafael', 'rafaelalves', 'Rafael Alves'),
        contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
      ],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))

    expect(screen.getByText('Contatos')).toBeTruthy()
    expect(await screen.findByText('@rafaelalves')).toBeTruthy()
    const contactSearch = screen.getByLabelText(/buscar contato/i)
    await user.type(contactSearch, 'ana')
    expect(screen.getByText('@anabeatriz')).toBeTruthy()
    expect(screen.queryByText('@rafaelalves')).toBeNull()
    await user.clear(contactSearch)
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
    expect(document.activeElement).toBe(usernameInput)

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

    await user.keyboard('{Escape}')
    expect(screen.queryByRole('dialog', { name: /adicionar contato/i })).toBeNull()
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

  it('requires a username before requesting a new contact', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({})
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const dialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    await user.click(within(dialog).getByRole('button', { name: /adicionar/i }))

    expect(within(dialog).getByText('Usuario obrigatorio')).toBeTruthy()
    expect(within(dialog).getByText('Informe o @usuario que deseja adicionar.')).toBeTruthy()
    expect(fetchMock).not.toHaveBeenCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({ method: 'POST' }),
    )
  })

  it('opens a private conversation from a contact', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      contacts: [contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz')],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await screen.findByText('@anabeatriz')

    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, {
        conversation: privateConversationResponse('conversation-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
      }),
    )
    fetchMock.mockResolvedValueOnce(historyResponse())

    await user.click(screen.getByRole('button', { name: /abrir conversa com ana beatriz/i }))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/private',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ user_id: 'user-ana' }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/conversation-ana/messages?limit=30',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(await screen.findByText('Conversa iniciada')).toBeTruthy()
    expect(screen.getByText('Nenhuma mensagem nesta conversa.')).toBeTruthy()
  })

  it('loads and paginates persisted history for a backend conversation', async () => {
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
    fetchMock.mockResolvedValueOnce(
      historyResponse({
        messages: [
          historyMessageResponse('message-2', 'Mensagem mais recente', 'user-current', 'Patric', '2026-07-22T13:49:00Z'),
        ],
        nextCursor: 'older-cursor',
        hasMore: true,
      }),
    )

    await user.click(screen.getByRole('button', { name: /abrir conversa com ana beatriz/i }))

    expect(await screen.findByText('Mensagem mais recente')).toBeTruthy()

    fetchMock.mockResolvedValueOnce(
      historyResponse({
        messages: [historyMessageResponse('message-1', 'Mensagem anterior', 'user-ana', 'Ana Beatriz', '2026-07-22T13:40:00Z')],
        nextCursor: null,
        hasMore: false,
      }),
    )

    await user.click(screen.getByRole('button', { name: /carregar mensagens anteriores/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/conversation-ana/messages?limit=30&before=older-cursor',
      expect.objectContaining({ method: 'GET' }),
    )
    expect(await screen.findByText('Mensagem anterior')).toBeTruthy()
    expect(screen.queryByRole('button', { name: /carregar mensagens anteriores/i })).toBeNull()
  })

  it('loads persisted history for conversations restored from the authenticated inbox', async () => {
    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [
        inboxSummaryResponse({
          id: 'conversation-ana',
          title: 'Ana Beatriz',
          senderId: 'user-current',
          body: 'Preview antes do reload',
          unreadCount: 0,
        }),
      ],
      historyMessages: [
        historyMessageResponse(
          'message-after-reload',
          'Mensagem recuperada depois do reload',
          'user-current',
          'Patric',
          '2026-07-22T13:49:00Z',
        ),
      ],
    })
    vi.stubGlobal('fetch', fetchMock)

    authenticate(pinia)

    expect(await screen.findByText('Mensagem recuperada depois do reload')).toBeTruthy()
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        'http://localhost:4000/api/conversations/conversation-ana/messages?limit=30',
        expect.objectContaining({
          method: 'GET',
          headers: expect.objectContaining({
            Authorization: 'Bearer jwt-token',
          }),
        }),
      ),
    )
  })

  it('aborts the previous history request when switching conversations', async () => {
    const user = userEvent.setup()
    const firstHistoryRequest: { signal?: AbortSignal } = {}
    const conversations = [
      inboxSummaryResponse({
        id: 'conversation-ana',
        title: 'Ana Beatriz',
        senderId: 'user-ana',
        body: 'Preview da Ana',
        unreadCount: 0,
      }),
      inboxSummaryResponse({
        id: 'conversation-bruno',
        title: 'Bruno Lima',
        senderId: 'user-bruno',
        body: 'Preview do Bruno',
        unreadCount: 0,
      }),
    ]
    const fetchMock = vi.fn((url: string | URL | Request, init?: RequestInit) => {
      const href = typeof url === 'string' ? url : url instanceof URL ? url.href : url.url
      const method = init?.method ?? 'GET'

      if (href === 'http://localhost:4000/api/contacts' && method === 'GET') {
        return Promise.resolve(jsonResponse(200, { contacts: [] }))
      }

      if (href === 'http://localhost:4000/api/conversations' && method === 'GET') {
        return Promise.resolve(jsonResponse(200, { conversations }))
      }

      if (
        href === 'http://localhost:4000/api/conversations/conversation-ana/messages?limit=30' &&
        method === 'GET'
      ) {
        firstHistoryRequest.signal = init?.signal ?? undefined

        return new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener(
            'abort',
            () => reject(new DOMException('The operation was aborted.', 'AbortError')),
            { once: true },
          )
        })
      }

      if (
        href === 'http://localhost:4000/api/conversations/conversation-bruno/messages?limit=30' &&
        method === 'GET'
      ) {
        return Promise.resolve(
          historyResponse({
            messages: [
              {
                ...historyMessageResponse(
                  'message-bruno',
                  'Mensagem atual do Bruno',
                  'user-bruno',
                  'Bruno Lima',
                  '2026-07-22T13:49:00Z',
                ),
                conversation_id: 'conversation-bruno',
              },
            ],
          }),
        )
      }

      return Promise.resolve(
        jsonResponse(500, {
          errors: {
            code: 'unexpected_test_request',
            detail: `Unexpected test request: ${method} ${href}`,
          },
        }),
      )
    })

    const { pinia } = await renderInbox()
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await waitFor(() => expect(firstHistoryRequest.signal).toBeDefined())
    await user.click(await screen.findByRole('button', { name: /bruno lima/i }))

    expect(await screen.findByText('Mensagem atual do Bruno')).toBeTruthy()
    expect(firstHistoryRequest.signal?.aborted).toBe(true)
    expect(screen.queryByText('Mensagem da conversa A')).toBeNull()
  })

  it('shows a history load error for a backend conversation', async () => {
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
    fetchMock.mockResolvedValueOnce(
      jsonResponse(400, {
        errors: {
          code: 'invalid_cursor',
          detail: 'The pagination cursor is invalid',
        },
      }),
    )

    await user.click(screen.getByRole('button', { name: /abrir conversa com ana beatriz/i }))

    expect(await screen.findByText('O cursor de paginação é inválido.')).toBeTruthy()
  })

  it('opens conversation search and clears the draft when sending', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    vi.stubGlobal('fetch', mockAuthenticatedFetch({ conversations: [defaultAnaInboxSummary()] }))
    authenticate(pinia)
    await waitFor(() => expect(sockets).toHaveLength(1))
    await screen.findAllByText('Ana Beatriz')
    sockets[0].channelFor('user:user-current').okJoin()
    sockets[0].channelFor('conversation:ana').okJoin()

    await user.click(screen.getByRole('button', { name: /buscar na conversa/i }))

    expect(screen.getByLabelText(/buscar na conversa/i)).toBeTruthy()
    expect(screen.getByText('0 / 0')).toBeTruthy()

    const messageInput = screen.getByLabelText(/^mensagem$/i) as HTMLTextAreaElement

    await user.type(messageInput, 'Mensagem de teste')
    await user.click(screen.getByRole('button', { name: /enviar mensagem/i }))

    expect(messageInput.value).toBe('')
  })

  it('filters authenticated inbox summaries through the documented query parameter', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [
        defaultAnaInboxSummary(),
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
      filteredConversations: [defaultAnaInboxSummary()],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await screen.findByText('Time de Produto')
    await user.type(screen.getByLabelText(/buscar conversa/i), 'ana')

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        'http://localhost:4000/api/conversations?q=ana',
        expect.objectContaining({ method: 'GET' }),
      ),
    )
    expect(screen.getByRole('button', { name: /ana beatriz/i })).toBeTruthy()
    expect(screen.queryByText('Time de Produto')).toBeNull()
  })

  it('keeps only the latest inbox search result when a previous request is cancelled', async () => {
    const { pinia } = await renderInbox()
    const conversations = [
      defaultAnaInboxSummary(),
      inboxSummaryResponse({
        id: 'group-product',
        type: 'group',
        title: 'Time de Produto',
        senderId: 'user-rafael',
        body: 'Mensagem do grupo',
        unreadCount: 0,
        memberCount: 3,
      }),
    ]
    const staleSearch: { signal?: AbortSignal } = {}
    const fetchMock = vi.fn((url: string | URL | Request, init?: RequestInit) => {
      const href = typeof url === 'string' ? url : url instanceof URL ? url.href : url.url
      const method = init?.method ?? 'GET'

      if (href === 'http://localhost:4000/api/contacts' && method === 'GET') {
        return Promise.resolve(jsonResponse(200, { contacts: [] }))
      }

      if (href === 'http://localhost:4000/api/conversations' && method === 'GET') {
        return Promise.resolve(jsonResponse(200, { conversations }))
      }

      if (href === 'http://localhost:4000/api/conversations?q=an' && method === 'GET') {
        staleSearch.signal = init?.signal ?? undefined

        return new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener(
            'abort',
            () => reject(new DOMException('The operation was aborted.', 'AbortError')),
            { once: true },
          )
        })
      }

      if (href === 'http://localhost:4000/api/conversations?q=ana' && method === 'GET') {
        return Promise.resolve(jsonResponse(200, { conversations: [defaultAnaInboxSummary()] }))
      }

      if (
        href.startsWith('http://localhost:4000/api/conversations/') &&
        href.includes('/messages?') &&
        method === 'GET'
      ) {
        return Promise.resolve(historyResponse())
      }

      return Promise.resolve(
        jsonResponse(500, {
          errors: {
            code: 'unexpected_test_request',
            detail: `Unexpected test request: ${method} ${href}`,
          },
        }),
      )
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await screen.findByText('Time de Produto')
    const searchInput = screen.getByLabelText(/buscar conversa/i)
    await fireEvent.update(searchInput, 'an')
    await waitFor(() => expect(staleSearch.signal).toBeDefined())

    await fireEvent.update(searchInput, 'ana')

    expect(await screen.findByRole('button', { name: /ana beatriz/i })).toBeTruthy()
    await waitFor(() => expect(screen.queryByText('Time de Produto')).toBeNull())
    expect(staleSearch.signal?.aborted).toBe(true)
  })

  it('loads group members when opening details from an inbox summary', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [
        inboxSummaryResponse({
          id: 'group-product',
          type: 'group',
          title: 'Time de Produto',
          senderId: 'user-rafael',
          body: 'Mensagem do grupo',
          unreadCount: 0,
          memberCount: 3,
        }),
      ],
      conversationDetails: groupResponse(),
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(await screen.findByRole('button', { name: /time de produto/i }))
    await user.click(screen.getByRole('button', { name: /gerenciar grupo/i }))

    expect(await screen.findByText('@anabeatriz')).toBeTruthy()
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/group-product',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({ Authorization: 'Bearer jwt-token' }),
      }),
    )
  })

  it('keeps a group member visible and reports the API error when removal fails', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [
        inboxSummaryResponse({
          id: 'group-product',
          type: 'group',
          title: 'Time de Produto',
          senderId: 'user-rafael',
          body: 'Mensagem do grupo',
          unreadCount: 0,
          memberCount: 3,
        }),
      ],
      conversationDetails: groupResponse(),
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(await screen.findByRole('button', { name: /time de produto/i }))
    await user.click(screen.getByRole('button', { name: /gerenciar grupo/i }))
    const removeAnaButton = await screen.findByRole('button', { name: /remover ana beatriz/i })

    fetchMock.mockResolvedValueOnce(
      jsonResponse(403, {
        errors: {
          code: 'forbidden',
          detail: 'Only the group creator can manage members',
        },
      }),
    )
    await user.click(removeAnaButton)

    expect((await screen.findByRole('alert')).textContent).toContain(
      'Apenas o criador do grupo pode gerenciar membros.',
    )
    expect(screen.getByRole('button', { name: /remover ana beatriz/i })).toBeTruthy()
  })

  it('searches messages in the selected conversation and navigates returned matches', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [defaultAnaInboxSummary()],
      searchResult: {
        messages: [
          searchHitResponse('message-1', 'Ajustei o cronograma final', 1, [{ start: 10, length: 10 }]),
          searchHitResponse('message-2', 'Familia alinhou o cronograma', 2, [{ start: 0, length: 7 }]),
        ],
        total_matches: 2,
        next_cursor: null,
        has_more: false,
      },
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /buscar na conversa/i }))
    await user.type(screen.getByLabelText(/buscar na conversa/i), 'cronograma')

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        'http://localhost:4000/api/conversations/ana/messages/search?q=cronograma&limit=100',
        expect.objectContaining({ method: 'GET' }),
      ),
    )
    expect(await screen.findByText('1 / 2')).toBeTruthy()
    expect(screen.getByText('cronograma')).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /proximo resultado/i }))

    expect(screen.getByText('2 / 2')).toBeTruthy()
    expect(screen.getByText('Familia')).toBeTruthy()
  })

  it('closes and resets conversation search when focus moves outside its controls', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    vi.stubGlobal('fetch', mockAuthenticatedFetch({ conversations: [defaultAnaInboxSummary()] }))
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /buscar na conversa/i }))
    const searchInput = screen.getByRole('textbox', { name: /buscar na conversa/i }) as HTMLInputElement
    await user.type(searchInput, 'x')

    expect(await screen.findByText('Digite pelo menos 2 caracteres.')).toBeTruthy()

    await user.click(screen.getByLabelText(/^mensagem$/i))

    expect(screen.queryByRole('textbox', { name: /buscar na conversa/i })).toBeNull()
    await user.click(screen.getByRole('button', { name: /buscar na conversa/i }))

    expect((screen.getByRole('textbox', { name: /buscar na conversa/i }) as HTMLInputElement).value).toBe('')
    expect(screen.getByText('0 / 0')).toBeTruthy()
  })

  it('keeps the message draft when realtime sending is unavailable', async () => {
    const user = userEvent.setup()

    await renderInbox()

    const messageInput = screen.getByLabelText(/^mensagem$/i) as HTMLTextAreaElement
    await user.type(messageInput, 'Mensagem ainda nao enviada')
    await user.keyboard('{Control>}{Enter}{/Control}')

    expect(messageInput.value).toBe('Mensagem ainda nao enviada')
    expect(sockets).toHaveLength(0)
  })

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

  it('validates the group name and contact selection before requesting creation', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({})
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /novo grupo/i }))
    await user.click(screen.getByRole('button', { name: /criar grupo/i }))

    expect(screen.getByRole('alert').textContent).toContain('Informe o nome do grupo.')
    expect(fetchMock).not.toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/groups',
      expect.objectContaining({ method: 'POST' }),
    )

    await user.type(screen.getByLabelText(/nome do grupo/i), 'Time sem membros')
    await user.click(screen.getByRole('button', { name: /criar grupo/i }))

    expect(screen.getByRole('alert').textContent).toContain('Selecione pelo menos um contato.')
    expect(fetchMock).not.toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/groups',
      expect.objectContaining({ method: 'POST' }),
    )
  })

  it('creates and manages a group from contacts', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      contacts: [
        contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
        contactResponse('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva'),
        contactResponse('contact-leticia', 'user-leticia', 'leticia', 'Leticia Moraes'),
      ],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /novo grupo/i }))
    await user.click(screen.getByLabelText(/ana beatriz/i))
    await user.click(screen.getByLabelText(/carlos silva/i))

    fetchMock.mockResolvedValueOnce(jsonResponse(201, { conversation: groupResponse() }))
    fetchMock.mockResolvedValueOnce(historyResponse())

    await user.clear(screen.getByLabelText(/nome do grupo/i))
    await user.type(screen.getByLabelText(/nome do grupo/i), 'Time de Produto')
    await user.click(screen.getByRole('button', { name: /criar grupo/i }))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/groups',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ name: 'Time de Produto', member_ids: ['user-ana', 'user-carlos'] }),
      }),
    )
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/group-product/messages?limit=30',
      expect.objectContaining({ method: 'GET' }),
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

    fetchMock.mockResolvedValueOnce(jsonResponse(204, null))
    await user.click(screen.getByRole('button', { name: /sair do grupo/i }))

    expect(screen.queryByText('Time de Produto')).toBeNull()
  })

  it('loads authenticated inbox summaries, renders unread badges, and marks a selected conversation read', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [
        inboxSummaryResponse({
          id: 'conversation-ana',
          title: 'Ana Beatriz',
          senderId: 'user-current',
          body: 'Perfeito, fico no aguardo entao',
          unreadCount: 7,
        }),
        inboxSummaryResponse({
          id: 'group-product',
          type: 'group',
          title: 'Time de Produto',
          senderId: 'user-rafael',
          body: 'Bom dia pessoal! Subi a build de staging pra validacao',
          unreadCount: 99,
          unreadOverflow: true,
          memberCount: 5,
        }),
      ],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    expect(await screen.findByText('Voce: Perfeito, fico no aguardo entao')).toBeTruthy()
    expect(await screen.findByLabelText('7 mensagens nao lidas')).toBeTruthy()
    expect(screen.getByLabelText('99+ mensagens nao lidas')).toBeTruthy()

    fetchMock.mockResolvedValueOnce(
      jsonResponse(200, {
        conversation_id: 'conversation-ana',
        last_read_at: '2026-07-22T14:30:11.204518Z',
        unread_count: 0,
      }),
    )

    await user.click(screen.getByRole('button', { name: /ana beatriz/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/conversation-ana/read',
      expect.objectContaining({ method: 'POST' }),
    )
    expect(screen.queryByLabelText('7 mensagens nao lidas')).toBeNull()
    expect(screen.getByLabelText('99+ mensagens nao lidas')).toBeTruthy()
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
      online: false,
    },
  }
}

function inboxSummaryResponse(
  options: {
    id: string
    title: string
    senderId: string
    body: string
    unreadCount: number
    type?: 'private' | 'group'
    unreadOverflow?: boolean
    memberCount?: number
    lastSeenAt?: string | null
    online?: boolean
  },
) {
  return {
    id: options.id,
    type: options.type ?? 'private',
    title: options.title,
    counterpart:
      options.type === 'group'
        ? null
        : {
            id: 'user-ana',
            username: 'anabeatriz',
            name: options.title,
            last_seen_at: options.lastSeenAt ?? null,
            online: options.online ?? false,
          },
    member_count: options.type === 'group' ? (options.memberCount ?? 3) : null,
    last_message: {
      id: `message-${options.id}`,
      body: options.body,
      sender_id: options.senderId,
      inserted_at: '2026-07-22T11:02:44.884210Z',
    },
    unread_count: options.unreadCount,
    unread_overflow: options.unreadOverflow ?? false,
    last_read_at: null,
  }
}

function defaultAnaInboxSummary() {
  return inboxSummaryResponse({
    id: 'ana',
    title: 'Ana Beatriz',
    senderId: 'user-ana',
    body: 'Perfeito, fico no aguardo entao',
    unreadCount: 0,
  })
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
      online: false,
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
    online: false,
  }
}

function historyResponse(
  options: {
    messages?: ReturnType<typeof historyMessageResponse>[]
    nextCursor?: string | null
    hasMore?: boolean
  } = {},
) {
  return jsonResponse(200, {
    messages: options.messages ?? [],
    next_cursor: options.nextCursor ?? null,
    has_more: options.hasMore ?? false,
  })
}

function historyMessageResponse(id: string, body: string, senderId: string, senderName: string, insertedAt: string) {
  return {
    id,
    conversation_id: 'conversation-ana',
    body,
    inserted_at: insertedAt,
    sender: {
      id: senderId,
      username: senderName.toLowerCase().replaceAll(' ', ''),
      name: senderName,
      last_seen_at: null,
      online: false,
    },
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function mockAuthenticatedFetch(options: {
  contacts?: unknown[]
  conversations?: unknown[]
  filteredConversations?: unknown[]
  historyMessages?: unknown[]
  conversationDetails?: unknown
  searchResult?: unknown
}) {
  const conversations = options.conversations ?? []
  const filteredConversations = options.filteredConversations ?? conversations

  const fetchMock = vi.fn((url: string | URL | Request, init?: RequestInit) => {
    const href = typeof url === 'string' ? url : url instanceof URL ? url.href : url.url
    const method = init?.method ?? 'GET'

    if (href === 'http://localhost:4000/api/contacts' && method === 'GET') {
      return Promise.resolve(jsonResponse(200, { contacts: options.contacts ?? [] }))
    }

    if (href === 'http://localhost:4000/api/conversations' && method === 'GET') {
      return Promise.resolve(jsonResponse(200, { conversations }))
    }

    if (href.startsWith('http://localhost:4000/api/conversations?q=') && method === 'GET') {
      return Promise.resolve(jsonResponse(200, { conversations: filteredConversations }))
    }

    if (href === 'http://localhost:4000/api/conversations/group-product' && method === 'GET') {
      return Promise.resolve(jsonResponse(200, { conversation: options.conversationDetails ?? groupResponse() }))
    }

    if (href.startsWith('http://localhost:4000/api/conversations/ana/messages/search?') && method === 'GET') {
      return Promise.resolve(
        jsonResponse(
          200,
          options.searchResult ?? {
            messages: [],
            total_matches: 0,
            next_cursor: null,
            has_more: false,
          },
        ),
      )
    }

    if (
      href.startsWith('http://localhost:4000/api/conversations/') &&
      href.includes('/messages?') &&
      method === 'GET'
    ) {
      return Promise.resolve(
        jsonResponse(200, {
          messages: options.historyMessages ?? [],
          next_cursor: null,
          has_more: false,
        }),
      )
    }

    return Promise.resolve(
      jsonResponse(500, {
        errors: {
          code: 'unexpected_test_request',
          detail: `Unexpected test request: ${method} ${href}`,
        },
      }),
    )
  })

  return fetchMock
}

function searchHitResponse(
  id: string,
  body: string,
  position: number,
  matchOffsets: Array<{ start: number; length: number }>,
) {
  return {
    ...realtimeMessageResponse({
      id,
      body,
      senderId: 'user-ana',
      senderName: 'Ana Beatriz',
    }),
    position,
    match_offsets: matchOffsets,
  }
}

function realtimeMessageResponse({
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
      online: false,
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
  offEvents: string[] = []

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

  off(event: string): void {
    this.offEvents.push(event)
  }

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
  private nextStateRef = 0
  private stateCallbacks = new Map<string, { state: SocketState; callback: () => void }>()

  constructor(token: string) {
    this.token = token
  }

  connect(): void {
    this.connected = true
  }

  disconnect(): void {
    this.disconnected = true
  }

  onOpen(callback: () => void): string {
    return this.registerStateCallback('open', callback)
  }

  onClose(callback: () => void): string {
    return this.registerStateCallback('close', callback)
  }

  onError(callback: (reason: unknown) => void): string {
    return this.registerStateCallback('error', () => callback(new Error('socket error')))
  }

  off(refs: string | string[]): void {
    for (const ref of Array.isArray(refs) ? refs : [refs]) {
      this.stateCallbacks.delete(ref)
    }
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

  emitOpen(): void {
    this.emitState('open')
  }

  emitClose(): void {
    this.emitState('close')
  }

  private emitState(state: SocketState): void {
    for (const entry of this.stateCallbacks.values()) {
      if (entry.state === state) {
        entry.callback()
      }
    }
  }

  private registerStateCallback(state: SocketState, callback: () => void): string {
    const ref = `socket-ref-${++this.nextStateRef}`
    this.stateCallbacks.set(ref, { state, callback })
    return ref
  }
}

type SocketState = 'open' | 'close' | 'error'
