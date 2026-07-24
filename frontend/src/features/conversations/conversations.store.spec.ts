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

  it('increments unread from a realtime update and caps the overflow badge', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          conversations: [inboxSummaryResponse({ unreadCount: 99, unreadOverflow: false })],
        }),
      ),
    )

    const store = useConversationsStore()
    await store.loadInbox('jwt-token')

    store.applyRealtimeUnread({
      conversationId: 'conversation-ana',
      lastMessage: {
        preview: 'nova mensagem',
        senderId: 'user-ana',
        insertedAt: '2026-07-23T14:00:00Z',
      },
      unread: true,
    })

    expect(store.inboxSummaries[0]).toMatchObject({ unreadCount: 100, unreadOverflow: true })
  })

  it('clears unread state from realtime and ignores unrelated conversations', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          conversations: [inboxSummaryResponse({ unreadCount: 4, unreadOverflow: true })],
        }),
      ),
    )

    const store = useConversationsStore()
    await store.loadInbox('jwt-token')

    store.applyRealtimeUnread(conversationUpdate('another-conversation', true))
    expect(store.inboxSummaries[0]).toMatchObject({ unreadCount: 4, unreadOverflow: true })

    store.applyRealtimeUnread(conversationUpdate('conversation-ana', false))
    expect(store.inboxSummaries[0]).toMatchObject({ unreadCount: 0, unreadOverflow: false })
  })

  it('upserts private conversations and always clears pending user state', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(200, { conversation: privateConversationResponse('Ana') }))
      .mockResolvedValueOnce(jsonResponse(200, { conversation: privateConversationResponse('Ana Atualizada') }))
      .mockResolvedValueOnce(
        jsonResponse(403, {
          errors: { code: 'forbidden', detail: 'You are not allowed to perform this action' },
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const store = useConversationsStore()
    await store.openPrivate('user-ana', 'jwt-token')
    await store.loadConversation('conversation-ana', 'jwt-token')

    expect(store.conversations).toHaveLength(1)
    expect(store.conversations[0]).toMatchObject({
      id: 'conversation-ana',
      counterpart: { name: 'Ana Atualizada' },
    })
    expect(store.pendingPrivateUserIds.has('user-ana')).toBe(false)

    await expect(store.openPrivate('user-ana', 'jwt-token')).rejects.toMatchObject({
      code: 'forbidden',
    })
    expect(store.pendingPrivateUserIds.has('user-ana')).toBe(false)
  })

  it('creates groups and clears saving state after success and failure', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(201, { conversation: groupConversationResponse() }))
      .mockResolvedValueOnce(
        jsonResponse(422, {
          errors: { code: 'validation_error', detail: 'The request could not be processed' },
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const store = useConversationsStore()
    await store.createGroup('Produto', ['user-ana'], 'jwt-token')

    expect(store.conversations[0]).toMatchObject({ id: 'group-product', name: 'Produto' })
    expect(store.isSavingGroup).toBe(false)

    await expect(
      store.createGroup('Inválido', ['user-ana'], 'jwt-token'),
    ).rejects.toMatchObject({ code: 'validation_error' })
    expect(store.isSavingGroup).toBe(false)
  })

  it('adds and removes group members while cleaning pending state', async () => {
    const withCarlos = groupConversationResponse({
      members: [
        groupMemberResponse('user-current', 'patric', 'Patric'),
        groupMemberResponse('user-ana', 'ana', 'Ana'),
        groupMemberResponse('user-carlos', 'carlos', 'Carlos'),
      ],
      member_count: 3,
    })
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(201, { conversation: groupConversationResponse() }))
      .mockResolvedValueOnce(jsonResponse(200, { conversation: withCarlos }))
      .mockResolvedValueOnce(new Response(null, { status: 204 }))
    vi.stubGlobal('fetch', fetchMock)

    const store = useConversationsStore()
    await store.createGroup('Produto', ['user-ana'], 'jwt-token')
    await store.addMembers('group-product', ['user-carlos'], 'jwt-token')

    expect(store.conversations[0]).toMatchObject({ memberCount: 3 })
    expect(store.pendingMemberUserIds.size).toBe(0)

    await store.removeMember('group-product', 'user-carlos', 'jwt-token')

    expect(store.conversations[0]).toMatchObject({ memberCount: 2 })
    expect(
      store.conversations[0]?.type === 'group'
        ? store.conversations[0].members.map((member) => member.id)
        : [],
    ).not.toContain('user-carlos')
    expect(store.pendingMemberUserIds.size).toBe(0)
  })

  it('cleans member pending state when membership requests fail', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementation(() =>
        Promise.resolve(
        jsonResponse(403, {
          errors: { code: 'forbidden', detail: 'Only the group creator can manage members' },
        }),
        ),
      ),
    )

    const store = useConversationsStore()

    await expect(
      store.addMembers('group-product', ['user-carlos'], 'jwt-token'),
    ).rejects.toMatchObject({ code: 'forbidden' })
    expect(store.pendingMemberUserIds.size).toBe(0)

    await expect(
      store.removeMember('group-product', 'user-carlos', 'jwt-token'),
    ).rejects.toMatchObject({ code: 'forbidden' })
    expect(store.pendingMemberUserIds.size).toBe(0)
  })

  it('removes conversations on leave and resets all feature state', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(200, {
          conversations: [inboxSummaryResponse({ unreadCount: 2 })],
        }),
      )
      .mockResolvedValueOnce(jsonResponse(200, { conversation: privateConversationResponse('Ana') }))
      .mockResolvedValueOnce(new Response(null, { status: 204 }))
    vi.stubGlobal('fetch', fetchMock)

    const store = useConversationsStore()
    await store.loadInbox('jwt-token')
    await store.openPrivate('user-ana', 'jwt-token')
    await store.leave('conversation-ana', 'jwt-token')

    expect(store.conversations).toEqual([])
    expect(store.inboxSummaries).toEqual([])

    store.reset()
    expect(store.$state).toMatchObject({
      conversations: [],
      inboxSummaries: [],
      inboxLoadState: 'idle',
      inboxLoadError: null,
    })
    expect(store.pendingPrivateUserIds.size).toBe(0)
    expect(store.pendingMemberUserIds.size).toBe(0)
    expect(store.pendingReadIds.size).toBe(0)
  })
})

function conversationUpdate(conversationId: string, unread: boolean) {
  return {
    conversationId,
    lastMessage: {
      preview: 'nova mensagem',
      senderId: 'user-ana',
      insertedAt: '2026-07-23T14:00:00Z',
    },
    unread,
  }
}

function privateConversationResponse(name: string) {
  return {
    id: 'conversation-ana',
    type: 'private',
    last_read_at: null,
    counterpart: groupMemberResponse('user-ana', 'ana', name),
  }
}

function groupConversationResponse(overrides: Record<string, unknown> = {}) {
  return {
    id: 'group-product',
    type: 'group',
    name: 'Produto',
    creator_id: 'user-current',
    member_count: 2,
    last_read_at: null,
    members: [
      groupMemberResponse('user-current', 'patric', 'Patric'),
      groupMemberResponse('user-ana', 'ana', 'Ana'),
    ],
    ...overrides,
  }
}

function groupMemberResponse(id: string, username: string, name: string) {
  return {
    id,
    username,
    name,
    last_seen_at: null,
    online: false,
  }
}

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
