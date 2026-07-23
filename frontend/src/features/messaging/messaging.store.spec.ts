import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useMessagesStore } from './messaging.store'

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

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
