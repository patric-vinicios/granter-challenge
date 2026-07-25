import { flushPromises } from '@vue/test-utils'
import { computed, ref } from 'vue'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { jsonResponse } from '@/test/http'

import { useConversationSearch } from './useConversationSearch'

describe('useConversationSearch adaptable inputs', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('keeps the current ref/computed contract working', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        messages: [
          {
            ...messageResponse('message-1', 'agenda final'),
            position: 1,
            match_offsets: [{ start: 0, length: 6 }],
          },
        ],
        total_matches: 1,
        next_cursor: null,
        has_more: false,
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const query = ref('agenda')
    const search = useConversationSearch({
      token: ref('jwt-token'),
      conversationId: computed(() => 'conversation-1'),
      query: computed(() => query.value),
    })

    await flushPromises()

    expect(fetchMock).toHaveBeenCalledOnce()
    expect(search.status.value).toBe('success')
    expect(search.totalMatches.value).toBe(1)
  })

  it('accepts plain readonly inputs without requiring wrapper refs', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        messages: [
          {
            ...messageResponse('message-1', 'agenda final'),
            position: 1,
            match_offsets: [{ start: 0, length: 6 }],
          },
        ],
        total_matches: 1,
        next_cursor: null,
        has_more: false,
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const search = useConversationSearch({
      token: 'jwt-token',
      conversationId: 'conversation-1',
      query: 'agenda',
    })

    await flushPromises()

    expect(fetchMock).toHaveBeenCalledOnce()
    expect(search.status.value).toBe('success')
  })
})

function messageResponse(id: string, body: string) {
  return {
    id,
    conversation_id: 'conversation-1',
    body,
    inserted_at: '2026-07-22T11:02:44.884210Z',
    sender: {
      id: 'user-ana',
      username: 'anabeatriz',
      name: 'Ana Beatriz',
      last_seen_at: null,
    },
  }
}
