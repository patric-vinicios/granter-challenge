import { fireEvent, screen, waitFor } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, it, expect, vi } from 'vitest'

import { useConversationsStore } from '@/features/conversations/conversations.store'

import {
  authenticate,
  defaultAnaInboxSummary,
  historyMessageResponse,
  historyResponse,
  inboxSummaryResponse,
  jsonResponse,
  mockAuthenticatedFetch,
  renderInbox,
  resetInboxHarness,
} from './inbox/inboxTestHarness'

describe('Inbox navigation and summaries', () => {
  beforeEach(resetInboxHarness)
  afterEach(() => {
    vi.useRealTimers()
  })

  it('shows the default conversation and switches to another conversation', async () => {
    const user = userEvent.setup()
    const { pinia } = await renderInbox()
    vi.stubGlobal(
      'fetch',
      mockAuthenticatedFetch({
        conversations: [
          defaultAnaInboxSummary(),
          inboxSummaryResponse({
            id: 'group-product',
            type: 'group',
            title: 'Time de Produto',
            senderId: 'user-rafael',
            body: 'Build pronta para validar',
            unreadCount: 0,
            memberCount: 5,
          }),
        ],
        historyMessages: [
          historyMessageResponse(
            'message-group',
            'Build pronta para validar',
            'user-rafael',
            'Rafael Alves',
            '2026-07-22T11:02:44.884210Z',
          ),
        ],
      }),
    )
    authenticate(pinia)

    const groupButton = await screen.findByRole('button', { name: /time de produto/i })
    await user.click(groupButton)

    expect(screen.getByText('5 membros')).toBeTruthy()
    expect(await screen.findAllByText('Build pronta para validar')).not.toHaveLength(0)
    expect(screen.getByText('Rafael Alves')).toBeTruthy()
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

  it('does not keep locally opened groups that do not match the inbox search', async () => {
    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [
        defaultAnaInboxSummary(),
        inboxSummaryResponse({
          id: 'group-aws',
          type: 'group',
          title: 'aws',
          senderId: 'user-current',
          body: 'infra notes',
          unreadCount: 0,
          memberCount: 2,
        }),
      ],
      filteredConversations: [defaultAnaInboxSummary()],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)
    useConversationsStore(pinia).conversations = [
      {
        id: 'group-aws',
        type: 'group',
        name: 'aws',
        creatorId: 'user-current',
        memberCount: 2,
        lastReadAt: null,
        members: [],
      },
    ]

    expect(await screen.findByRole('button', { name: /aws/i })).toBeTruthy()

    await fireEvent.update(screen.getByLabelText(/buscar conversa/i), 'ana')

    expect(screen.getByRole('button', { name: /ana beatriz/i })).toBeTruthy()
    expect(screen.queryByRole('button', { name: /aws/i })).toBeNull()
  })

  it('restores inbox search and selected conversation from the URL', async () => {
    const { pinia } = await renderInbox('/inbox?q=produto&conversation=group-product')
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
      filteredConversations: [
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
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    expect((screen.getByLabelText(/buscar conversa/i) as HTMLInputElement).value).toBe('produto')
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        'http://localhost:4000/api/conversations?q=produto',
        expect.objectContaining({ method: 'GET' }),
      ),
    )
    expect(await screen.findByText('Bom dia pessoal! Subi a build de staging pra validacao')).toBeTruthy()
  })

  it('keeps inbox search and selected conversation in the URL', async () => {
    const user = userEvent.setup()

    const { pinia, router } = await renderInbox()
    vi.stubGlobal(
      'fetch',
      mockAuthenticatedFetch({
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
      }),
    )
    authenticate(pinia)

    await screen.findByText('Time de Produto')
    await user.type(screen.getByLabelText(/buscar conversa/i), 'produto')

    await waitFor(() => expect(router.currentRoute.value.query.q).toBe('produto'))
    expect(screen.getByText('Selecione uma conversa')).toBeTruthy()
    expect(router.currentRoute.value.query.conversation).toBeUndefined()

    await user.click(screen.getByRole('button', { name: /time de produto/i }))

    await waitFor(() => expect(router.currentRoute.value.query.conversation).toBe('group-product'))
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
    vi.useFakeTimers()
    const searchInput = screen.getByLabelText(/buscar conversa/i)
    await fireEvent.update(searchInput, 'an')
    await vi.advanceTimersByTimeAsync(800)
    await waitFor(() => expect(staleSearch.signal).toBeDefined())

    await fireEvent.update(searchInput, 'ana')
    await vi.advanceTimersByTimeAsync(800)

    expect(await screen.findByRole('button', { name: /ana beatriz/i })).toBeTruthy()
    await waitFor(() => expect(screen.queryByText('Time de Produto')).toBeNull())
    expect(staleSearch.signal?.aborted).toBe(true)
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

  it('logs out from the inbox, revokes the session and returns to login', async () => {
    const user = userEvent.setup()
    const { pinia, router } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({ conversations: [defaultAnaInboxSummary()] })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)
    window.localStorage.setItem('granter.session', JSON.stringify({ token: 'jwt-token' }))
    await screen.findByRole('button', { name: /ana beatriz/i })

    fetchMock.mockResolvedValueOnce(new Response(null, { status: 204 }))
    await user.click(screen.getByRole('button', { name: 'Sair' }))

    await waitFor(() => expect(router.currentRoute.value.path).toBe('/'))
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/auth/session',
      expect.objectContaining({
        method: 'DELETE',
        headers: expect.objectContaining({ Authorization: 'Bearer jwt-token' }),
      }),
    )
    expect(window.localStorage.getItem('granter.session')).toBeNull()
  })
})
