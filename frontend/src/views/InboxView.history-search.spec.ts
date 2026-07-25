import { screen, waitFor } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, it, expect, vi } from 'vitest'

import {
  authenticate,
  contactResponse,
  defaultAnaInboxSummary,
  historyMessageResponse,
  historyResponse,
  inboxSummaryResponse,
  jsonResponse,
  mockAuthenticatedFetch,
  privateConversationResponse,
  renderInbox,
  resetInboxHarness,
  searchHitResponse,
  sockets,
} from './inbox/inboxTestHarness'

describe('Inbox history and search', () => {
  beforeEach(resetInboxHarness)

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

  it('searches messages in the selected conversation and navigates returned matches', async () => {
    const user = userEvent.setup()
    const scrollIntoView = mockScrollIntoView()

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
    await waitFor(() => expect(scrollIntoView).toHaveBeenCalledTimes(1))

    await user.click(screen.getByRole('button', { name: /proximo resultado/i }))

    expect(screen.getByText('2 / 2')).toBeTruthy()
    expect(screen.getByText('Familia')).toBeTruthy()
    await waitFor(() => expect(scrollIntoView).toHaveBeenCalledTimes(2))
  })

  it('scrolls to a far search result and places it before the current loaded page', async () => {
    const user = userEvent.setup()
    const scrollIntoView = mockScrollIntoView()
    const currentPageMessages = Array.from({ length: 30 }, (_, index) =>
      historyMessageResponse(
        `message-current-${index + 1}`,
        `Mensagem atual ${index + 1}`,
        'user-ana',
        'Ana Beatriz',
        `2026-07-22T10:${String(index % 60).padStart(2, '0')}:00Z`,
      ),
    )

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [defaultAnaInboxSummary()],
      historyMessages: currentPageMessages,
      searchResult: {
        messages: [
          {
            ...searchHitResponse('message-4500', 'Resultado distante encontrado', 4500, [
              { start: 20, length: 10 },
            ]),
            inserted_at: '2026-07-21T09:42:00Z',
          },
        ],
        total_matches: 5000,
        next_cursor: null,
        has_more: true,
      },
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await screen.findByText('Mensagem atual 30')
    await user.click(screen.getByRole('button', { name: /buscar na conversa/i }))
    await user.type(screen.getByLabelText(/buscar na conversa/i), 'distante')

    expect(await screen.findByText('4500 / 5000+')).toBeTruthy()
    expect(
      screen.getByText((_content, element) => element?.textContent === 'Resultado distante encontrado'),
    ).toBeTruthy()
    await waitFor(() => expect(scrollIntoView).toHaveBeenCalledTimes(1))

    const messageLog = screen.getByRole('log', { name: 'Mensagens da conversa' })
    const logText = messageLog.textContent ?? ''

    expect(logText.indexOf('Resultado distante encontrado')).toBeLessThan(
      logText.indexOf('Mensagem atual 1'),
    )
  })

  it('focuses conversation search when opened and keeps it open when focus moves outside', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    vi.stubGlobal('fetch', mockAuthenticatedFetch({ conversations: [defaultAnaInboxSummary()] }))
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /buscar na conversa/i }))
    const searchInput = screen.getByRole('textbox', { name: /buscar na conversa/i }) as HTMLInputElement
    expect(searchInput).toBe(document.activeElement)
    await user.type(searchInput, 'x')

    expect(await screen.findByText('Digite pelo menos 2 caracteres.')).toBeTruthy()

    await user.click(screen.getByLabelText(/^mensagem$/i))

    expect(screen.getByRole('textbox', { name: /buscar na conversa/i })).toBeTruthy()
    expect(searchInput.value).toBe('x')
    expect(screen.getByText('Digite pelo menos 2 caracteres.')).toBeTruthy()
  })
})

function mockScrollIntoView() {
  const scrollIntoView = vi.fn()

  Object.defineProperty(Element.prototype, 'scrollIntoView', {
    configurable: true,
    value: scrollIntoView,
  })

  return scrollIntoView
}
