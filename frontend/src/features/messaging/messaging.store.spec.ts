import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useMessagesStore, useMessagingStore } from './messaging.store'
import type { PersistedMessage } from './messaging.contracts'

describe('messages.store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.unstubAllGlobals()
  })

  it('loads the newest page for a conversation', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          messages: [messageResponse('message-2', 'mais nova')],
          next_cursor: 'cursor-older',
          has_more: true,
        }),
      ),
    )

    const store = useMessagesStore()

    await store.loadInitial('conversation-1', 'jwt-token')

    expect(store.histories['conversation-1']).toMatchObject({
      messages: [{ id: 'message-2', body: 'mais nova' }],
      nextCursor: 'cursor-older',
      hasMore: true,
      isLoadingInitial: false,
      error: null,
    })
  })

  it('prepends older pages and deduplicates by server id', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(200, {
          messages: [messageResponse('message-2', 'mais nova')],
          next_cursor: 'cursor-older',
          has_more: true,
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse(200, {
          messages: [messageResponse('message-1', 'antiga'), messageResponse('message-2', 'mais nova')],
          next_cursor: null,
          has_more: false,
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const store = useMessagesStore()

    await store.loadInitial('conversation-1', 'jwt-token')
    await store.loadOlder('conversation-1', 'jwt-token')

    expect(store.histories['conversation-1'].messages.map((message) => message.id)).toEqual([
      'message-1',
      'message-2',
    ])
    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/conversation-1/messages?limit=30&before=cursor-older',
      expect.any(Object),
    )
  })

  it('stores observable load errors', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(404, {
          errors: {
            code: 'not_found',
            detail: 'The requested resource was not found',
          },
        }),
      ),
    )

    const store = useMessagesStore()

    await store.loadInitial('conversation-1', 'jwt-token')

    expect(store.histories['conversation-1']).toMatchObject({
      isLoadingInitial: false,
      error: 'O recurso solicitado não foi encontrado.',
    })
  })

  it('treats aborted initial loads as retryable and silent', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockRejectedValue(new DOMException('The operation was aborted', 'AbortError')),
    )

    const store = useMessagesStore()
    await store.loadInitial('conversation-1', 'jwt-token')

    expect(store.histories['conversation-1']).toMatchObject({
      didLoadInitial: false,
      isLoadingInitial: false,
      error: null,
    })
  })

  it('queues one forced refresh while an initial load is in flight', async () => {
    let resolveInitial!: (response: Response) => void
    const initialResponse = new Promise<Response>((resolve) => {
      resolveInitial = resolve
    })
    const fetchMock = vi
      .fn()
      .mockReturnValueOnce(initialResponse)
      .mockResolvedValueOnce(
        jsonResponse(200, {
          messages: [messageResponse('message-2', 'atualizada')],
          next_cursor: null,
          has_more: false,
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const store = useMessagesStore()
    const firstLoad = store.loadInitial('conversation-1', 'jwt-token')
    await store.loadInitial('conversation-1', 'jwt-token', undefined, { force: true })

    expect(store.pendingRefreshIds.has('conversation-1')).toBe(true)

    resolveInitial(
      jsonResponse(200, {
        messages: [messageResponse('message-1', 'inicial')],
        next_cursor: null,
        has_more: false,
      }),
    )
    await firstLoad
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    await vi.waitFor(() =>
      expect(store.histories['conversation-1'].messages[0]?.id).toBe('message-2'),
    )

    expect(store.pendingRefreshIds.has('conversation-1')).toBe(false)
    expect(store.histories['conversation-1'].isLoadingInitial).toBe(false)
  })

  it('preserves the current history when a silent refresh fails', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(200, {
          messages: [messageResponse('message-1', 'persistida')],
          next_cursor: null,
          has_more: false,
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse(500, {
          errors: { code: 'internal_error', detail: 'Something went wrong' },
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const store = useMessagesStore()
    await store.loadInitial('conversation-1', 'jwt-token')
    await store.loadInitial('conversation-1', 'jwt-token', undefined, {
      force: true,
      silent: true,
    })

    expect(store.histories['conversation-1']).toMatchObject({
      messages: [{ id: 'message-1' }],
      isLoadingInitial: false,
      error: null,
    })
  })

  it('exposes older-page errors and does not request unavailable pages', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(200, {
          messages: [messageResponse('message-2', 'nova')],
          next_cursor: 'cursor-older',
          has_more: true,
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse(500, {
          errors: { code: 'internal_error', detail: 'Something went wrong' },
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const store = useMessagesStore()
    await store.loadOlder('missing', 'jwt-token')
    expect(fetchMock).not.toHaveBeenCalled()

    await store.loadInitial('conversation-1', 'jwt-token')
    await store.loadOlder('conversation-1', 'jwt-token')

    expect(store.histories['conversation-1']).toMatchObject({
      isLoadingOlder: false,
      error: 'Algo deu errado.',
    })
  })

  it('reconciles equal message bodies by client reference and keeps both persisted ids', () => {
    const store = useMessagingStore()

    store.addOptimisticMessage('conversation-1', 'ok', 'client-1')
    store.addOptimisticMessage('conversation-1', 'ok', 'client-2')
    store.confirmMessage(persistedMessage('message-1', 'ok'), 'user-ana', 'client-1')
    store.confirmMessage(persistedMessage('message-2', 'ok'), 'user-ana', 'client-2')

    const conversation = store.decorate({
      id: 'conversation-1',
      type: 'private',
      initials: 'AB',
      name: 'Ana Beatriz',
      subtitle: '',
      preview: '',
      time: '',
      messages: [],
    })

    expect(conversation.messages.map((message) => message.id)).toEqual(['message-1', 'message-2'])
  })

  it('does not duplicate a realtime message already present in the REST history', () => {
    const store = useMessagingStore()
    const message = persistedMessage('message-1', 'mensagem recebida')

    store.receiveMessage(message, 'user-current')

    const conversation = store.decorate({
      id: 'conversation-1',
      type: 'private',
      initials: 'AB',
      name: 'Ana Beatriz',
      subtitle: '',
      preview: '',
      time: '',
      messages: [
        {
          id: message.id,
          side: 'in',
          author: message.sender.name,
          text: message.body,
          time: '10:48',
        },
      ],
    })

    expect(conversation.messages.map((item) => item.id)).toEqual(['message-1'])
  })

  it('applies realtime updates, send failures, revocation and activity sorting', () => {
    const store = useMessagingStore()
    const sendError = {
      reason: 'rate_limited' as const,
      clientRef: 'client-1',
      retryAfterMs: 1000,
    }

    store.addOptimisticMessage('conversation-1', 'Mensagem longa '.repeat(4), 'client-1')
    store.failMessage('client-1', sendError)
    store.failMessage(null, { reason: 'unknown_event', clientRef: null })
    store.applyConversationUpdate(
      {
        conversationId: 'conversation-2',
        lastMessage: {
          preview: 'Resposta',
          senderId: 'user-current',
          insertedAt: '2026-07-24T11:00:00Z',
        },
        unread: false,
      },
      'user-current',
    )
    store.revokeConversation('conversation-1')

    expect(store.pendingErrors['client-1']).toEqual(sendError)
    expect(store.revokedConversationIds).toEqual(['conversation-1'])
    expect(store.decorate(conversationItem('conversation-1')).messages[0]).toMatchObject({
      clientRef: 'client-1',
      time: 'Enviando',
      wide: true,
    })
    expect(store.decorate(conversationItem('conversation-2')).preview).toBe('Voce: Resposta')
    expect(store.sortByActivity([
      conversationItem('conversation-1'),
      conversationItem('conversation-2'),
    ])[0]?.id).toBe('conversation-1')
  })

  it('appends acknowledgements without client refs and clears matching send failures', () => {
    const store = useMessagingStore()
    store.addOptimisticMessage('conversation-1', 'otimista', 'client-1')
    store.failMessage('client-1', {
      reason: 'validation_error',
      clientRef: 'client-1',
    })

    store.confirmMessage(persistedMessage('message-other', 'outra'), 'user-current', null)
    store.confirmMessage(persistedMessage('message-1', 'otimista'), 'user-current', 'client-1')

    expect(store.pendingErrors['client-1']).toBeUndefined()
    expect(
      store.decorate(conversationItem('conversation-1')).messages.map((message) => message.id),
    ).toEqual(['message-1', 'message-other'])
  })

  it('removes and resets cached histories and realtime conversations', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          messages: [messageResponse('message-1', 'persistida')],
          next_cursor: null,
          has_more: false,
        }),
      ),
    )

    const messages = useMessagesStore()
    const realtime = useMessagingStore()
    await messages.loadInitial('conversation-1', 'jwt-token')
    realtime.receiveMessage(persistedMessage('message-1', 'persistida'), 'user-current')

    messages.removeConversation('conversation-1')
    realtime.removeConversation('conversation-1')
    expect(messages.histories['conversation-1']).toBeUndefined()
    expect(realtime.conversations['conversation-1']).toBeUndefined()

    await messages.loadInitial('conversation-1', 'jwt-token')
    realtime.receiveMessage(persistedMessage('message-1', 'persistida'), 'user-current')
    messages.reset()
    realtime.reset()

    expect(messages.histories).toEqual({})
    expect(messages.pendingRefreshIds.size).toBe(0)
    expect(realtime.conversations).toEqual({})
    expect(realtime.pendingErrors).toEqual({})
  })

  it('exposes pending refresh coordination through Pinia state', () => {
    const store = useMessagesStore()

    expect(store.$state).toHaveProperty('pendingRefreshIds')
  })

  it('exposes realtime conversation state through Pinia state', () => {
    const store = useMessagingStore()

    expect(store.$state).toHaveProperty('conversations')
  })
})

function messageResponse(id: string, body: string) {
  return {
    id,
    conversation_id: 'conversation-1',
    body,
    inserted_at: '2026-07-22T13:48:17.123456Z',
    sender: {
      id: 'user-ana',
      username: 'anabeatriz',
      name: 'Ana Beatriz',
      last_seen_at: null,
    },
  }
}

function persistedMessage(id: string, body: string): PersistedMessage {
  return {
    id,
    conversationId: 'conversation-1',
    body,
    insertedAt: '2026-07-22T13:48:17.123456Z',
    sender: {
      id: 'user-ana',
      username: 'anabeatriz',
      name: 'Ana Beatriz',
      lastSeenAt: null,
      online: false,
    },
  }
}

function conversationItem(id: string) {
  return {
    id,
    type: 'private' as const,
    initials: 'AB',
    name: 'Ana Beatriz',
    subtitle: '',
    preview: '',
    time: '',
    messages: [],
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
