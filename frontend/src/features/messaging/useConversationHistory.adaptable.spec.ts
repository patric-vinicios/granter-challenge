import { createPinia, setActivePinia } from 'pinia'
import { ref } from 'vue'
import { flushPromises } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useConversationHistory } from './useConversationHistory'
import { useMessagesStore } from './messaging.store'

describe('useConversationHistory adaptable inputs', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.unstubAllGlobals()
  })

  it('keeps the current ref contract working for initial history loading', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        messages: [],
        next_cursor: 'cursor-older',
        has_more: true,
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    useConversationHistory({
      token: ref('jwt-token'),
      selectedConversationId: ref('conversation-1'),
      displayedConversationId: ref('conversation-1'),
      persistedConversationSources: [ref([{ id: 'conversation-1' }])],
    })

    await flushPromises()

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/conversation-1/messages?limit=30',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
  })

  it('lets initial history loading read token and ids from getters', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        messages: [],
        next_cursor: null,
        has_more: false,
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    useConversationHistory({
      token: () => 'jwt-token',
      selectedConversationId: () => 'conversation-1',
      displayedConversationId: () => 'conversation-1',
      persistedConversationSources: [() => [{ id: 'conversation-1' }]],
    })

    await flushPromises()

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/conversation-1/messages?limit=30',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
  })

  it('keeps local conversations empty and does not load without persistence', async () => {
    const messagesStore = useMessagesStore()
    const loadInitial = vi.spyOn(messagesStore, 'loadInitial')
    const history = useConversationHistory({
      token: 'jwt-token',
      selectedConversationId: 'local-conversation',
      displayedConversationId: 'local-conversation',
      persistedConversationSources: [[]],
    })

    await flushPromises()

    expect(loadInitial).not.toHaveBeenCalled()
    expect(history.state.value).toMatchObject({
      messages: [],
      didLoadInitial: false,
      error: null,
    })
  })

  it('aborts stale history loads when the selected conversation changes', async () => {
    const selectedConversationId = ref('conversation-1')
    const sources = ref([{ id: 'conversation-1' }, { id: 'conversation-2' }])
    const signals: AbortSignal[] = []
    const messagesStore = useMessagesStore()
    vi.spyOn(messagesStore, 'loadInitial').mockImplementation(
      async (_conversationId, _token, signal) => {
        if (signal) {
          signals.push(signal)
        }
      },
    )
    useConversationHistory({
      token: 'jwt-token',
      selectedConversationId,
      displayedConversationId: selectedConversationId,
      persistedConversationSources: [sources],
    })

    selectedConversationId.value = 'conversation-2'
    await flushPromises()

    expect(signals[0]?.aborted).toBe(true)
    expect(messagesStore.loadInitial).toHaveBeenLastCalledWith(
      'conversation-2',
      'jwt-token',
      expect.any(AbortSignal),
    )
  })

  it('loads older messages and refreshes the selected persisted conversation', () => {
    const token = ref<string | null>('jwt-token')
    const selectedConversationId = ref<string | null>('conversation-1')
    const messagesStore = useMessagesStore()
    const loadOlder = vi.spyOn(messagesStore, 'loadOlder').mockResolvedValue()
    const loadInitial = vi.spyOn(messagesStore, 'loadInitial').mockResolvedValue()
    const history = useConversationHistory({
      token,
      selectedConversationId,
      displayedConversationId: () => 'conversation-1',
      persistedConversationSources: [[{ id: 'conversation-1' }]],
    })
    loadInitial.mockClear()

    history.loadOlder()
    history.refresh()

    expect(loadOlder).toHaveBeenCalledWith('conversation-1', 'jwt-token')
    expect(loadInitial).toHaveBeenCalledWith(
      'conversation-1',
      'jwt-token',
      undefined,
      { force: true, silent: true },
    )

    token.value = null
    loadOlder.mockClear()
    loadInitial.mockClear()
    history.loadOlder()
    history.refresh()
    expect(loadOlder).not.toHaveBeenCalled()
    expect(loadInitial).not.toHaveBeenCalled()
  })
})

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
