import { createPinia, setActivePinia } from 'pinia'
import { nextTick, shallowRef } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { withSetup } from '@/test/composable'

import { useConversationsStore } from './conversations.store'
import { useInboxList } from './useInboxList'

describe('useInboxList', () => {
  let unmount: (() => void) | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
  })

  afterEach(() => unmount?.())

  it('loads reactively, aborts stale requests and selects the first available item', async () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    const store = useConversationsStore()
    const signals: AbortSignal[] = []
    vi.spyOn(store, 'loadInbox').mockImplementation(
      async (_token, signal) => {
        if (signal) {
          signals.push(signal)
        }
      },
    )
    const query = shallowRef('')
    const items = shallowRef([{ id: 'conversation-1' }])
    const selectedConversationId = shallowRef<string | null>(null)
    const setup = withSetup(
      () =>
        useInboxList({
          token: 'jwt-token',
          items,
          selectedConversationId,
          query,
        }),
      { pinia },
    )
    unmount = setup.unmount

    expect(selectedConversationId.value).toBe('conversation-1')
    expect(store.loadInbox).toHaveBeenCalledWith(
      'jwt-token',
      expect.any(AbortSignal),
      '',
    )

    query.value = 'produto'
    await nextTick()

    expect(signals[0]?.aborted).toBe(true)
    expect(store.loadInbox).toHaveBeenLastCalledWith(
      'jwt-token',
      expect.any(AbortSignal),
      'produto',
    )

    items.value = [{ id: 'conversation-2' }]
    await nextTick()
    expect(selectedConversationId.value).toBe('conversation-2')
  })

  it('stays idle without authentication and reports empty authenticated results', () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    const store = useConversationsStore()
    const loadInbox = vi.spyOn(store, 'loadInbox')
    const token = shallowRef<string | null>(null)
    const items = shallowRef<readonly { id: string }[]>([])
    const setup = withSetup(
      () =>
        useInboxList({
          token,
          items,
          selectedConversationId: shallowRef(null),
        }),
      { pinia },
    )
    unmount = setup.unmount

    expect(loadInbox).not.toHaveBeenCalled()
    expect(setup.result.isEmpty.value).toBe(false)

    token.value = 'jwt-token'
    store.inboxLoadState = 'success'
    expect(setup.result.isEmpty.value).toBe(true)
  })

  it('marks unread selections once and exposes mark-read failures', async () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    const store = useConversationsStore()
    store.inboxSummaries = [summary(3)]
    vi.spyOn(store, 'loadInbox').mockResolvedValue()
    const markRead = vi.spyOn(store, 'markRead').mockRejectedValue(new Error('failure'))
    const selectedConversationId = shallowRef<string | null>(null)
    const setup = withSetup(
      () =>
        useInboxList({
          token: 'jwt-token',
          items: [{ id: 'conversation-1' }],
          selectedConversationId,
        }),
      { pinia },
    )
    unmount = setup.unmount

    await setup.result.select('conversation-1')

    expect(selectedConversationId.value).toBe('conversation-1')
    expect(markRead).toHaveBeenCalledWith('conversation-1', 'jwt-token')
    expect(setup.result.error.value).toBe('failure')

    markRead.mockClear()
    store.inboxSummaries = [summary(0)]
    await setup.result.select('conversation-1')
    expect(markRead).not.toHaveBeenCalled()

    store.inboxSummaries = [summary(2)]
    store.pendingReadIds = new Set(['conversation-1'])
    await setup.result.select('conversation-1')
    expect(markRead).not.toHaveBeenCalled()
  })

  it('reloads the active query only while authenticated', async () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    const store = useConversationsStore()
    const loadInbox = vi.spyOn(store, 'loadInbox').mockResolvedValue()
    const token = shallowRef<string | null>(null)
    const query = shallowRef('ana')
    const setup = withSetup(
      () =>
        useInboxList({
          token,
          items: [],
          selectedConversationId: shallowRef(null),
          query,
        }),
      { pinia },
    )
    unmount = setup.unmount

    await setup.result.reload()
    expect(loadInbox).not.toHaveBeenCalled()

    token.value = 'jwt-token'
    await nextTick()
    loadInbox.mockClear()
    await setup.result.reload()

    expect(loadInbox).toHaveBeenCalledWith('jwt-token', undefined, 'ana')
  })
})

function summary(unreadCount: number) {
  return {
    id: 'conversation-1',
    type: 'private' as const,
    title: 'Ana',
    counterpart: {
      id: 'user-ana',
      username: 'ana',
      name: 'Ana',
      lastSeenAt: null,
      online: false,
    },
    memberCount: null,
    lastMessage: null,
    unreadCount,
    unreadOverflow: false,
    lastReadAt: null,
  }
}
