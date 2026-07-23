import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useConversationsStore } from './conversations.store'

describe('conversations.store inbox state', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.unstubAllGlobals()
  })

  it('loads inbox summaries from the backend contract', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          conversations: [inboxSummaryResponse({ unreadCount: 2 })],
        }),
      ),
    )

    const store = useConversationsStore()
    await store.loadInbox('jwt-token')

    expect(store.inboxLoadState).toBe('success')
    expect(store.inboxLoadError).toBeNull()
    expect(store.inboxSummaries).toEqual([
      expect.objectContaining({
        id: 'conversation-ana',
        title: 'Ana Beatriz',
        unreadCount: 2,
      }),
    ])
  })

  it('exposes a load error without discarding previous summaries', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(200, {
          conversations: [inboxSummaryResponse({ unreadCount: 1 })],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse(500, {
          errors: {
            code: 'internal_error',
            detail: 'Something went wrong',
          },
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const store = useConversationsStore()
    await store.loadInbox('jwt-token')
    await store.loadInbox('jwt-token')

    expect(store.inboxLoadState).toBe('error')
    expect(store.inboxLoadError).toBe('Algo deu errado.')
    expect(store.inboxSummaries).toHaveLength(1)
  })

  it('clears the matching unread badge after mark-read succeeds', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(200, {
          conversations: [inboxSummaryResponse({ unreadCount: 99, unreadOverflow: true })],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse(200, {
          conversation_id: 'conversation-ana',
          last_read_at: '2026-07-22T14:30:11.204518Z',
          unread_count: 0,
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const store = useConversationsStore()
    await store.loadInbox('jwt-token')
    await store.markRead('conversation-ana', 'jwt-token')

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/conversation-ana/read',
      expect.objectContaining({ method: 'POST' }),
    )
    expect(store.inboxSummaries[0]).toMatchObject({
      unreadCount: 0,
      unreadOverflow: false,
      lastReadAt: '2026-07-22T14:30:11.204518Z',
    })
    expect(store.pendingReadIds.has('conversation-ana')).toBe(false)
  })
})

function inboxSummaryResponse(options: { unreadCount: number; unreadOverflow?: boolean }) {
  return {
    id: 'conversation-ana',
    type: 'private',
    title: 'Ana Beatriz',
    counterpart: {
      id: 'user-ana',
      username: 'anabeatriz',
      name: 'Ana Beatriz',
      last_seen_at: null,
    },
    member_count: null,
    last_message: {
      id: 'message-latest',
      body: 'bom dia!',
      sender_id: 'user-ana',
      inserted_at: '2026-07-22T11:02:44.884210Z',
    },
    unread_count: options.unreadCount,
    unread_overflow: options.unreadOverflow ?? false,
    last_read_at: null,
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
