import { flushPromises } from '@vue/test-utils'
import { shallowRef } from 'vue'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { useConversationSearch } from './useConversationSearch'

describe('useConversationSearch', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it.each([
    ['', 'idle', null],
    ['x', 'validation', 'Digite pelo menos 2 caracteres.'],
    ['x'.repeat(101), 'validation', 'Digite no máximo 100 caracteres.'],
  ] as const)('validates query %j without a request', (query, status, error) => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    const search = useConversationSearch({
      token: 'jwt-token',
      conversationId: 'conversation-1',
      query,
    })

    expect(search.status.value).toBe(status)
    expect(search.error.value).toBe(error)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('requires authentication for server-backed searches', () => {
    const search = useConversationSearch({
      token: null,
      conversationId: 'conversation-1',
      query: 'agenda',
    })

    expect(search.status.value).toBe('validation')
    expect(search.error.value).toBe('Entre para buscar no servidor.')
  })

  it('resets when no conversation is selected', () => {
    const search = useConversationSearch({
      token: 'jwt-token',
      conversationId: null,
      query: 'agenda',
    })

    expect(search.status.value).toBe('idle')
    expect(search.error.value).toBeNull()
    expect(search.matches.value).toEqual([])
  })

  it('navigates matches forward and backward with wrapping', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          messages: [
            searchHit('message-1', 4),
            searchHit('message-2', 9),
          ],
          total_matches: 2,
          next_cursor: null,
          has_more: true,
        }),
      ),
    )
    const search = useConversationSearch({
      token: 'jwt-token',
      conversationId: 'conversation-1',
      query: 'agenda',
    })
    await flushPromises()

    expect(search.status.value).toBe('success')
    expect(search.activeHit.value?.message.id).toBe('message-1')
    expect(search.totalMatches.value).toBe(2)
    expect(search.truncated.value).toBe(true)

    search.selectNext()
    expect(search.activeHit.value?.message.id).toBe('message-2')
    search.selectNext()
    expect(search.activeHit.value?.message.id).toBe('message-1')
    search.selectPrevious()
    expect(search.activeHit.value?.message.id).toBe('message-2')
  })

  it('ignores stale responses after the query changes', async () => {
    vi.useFakeTimers()
    const staleResponse = deferred<Response>()
    const query = shallowRef('agenda')
    const fetchMock = vi
      .fn()
      .mockReturnValueOnce(staleResponse.promise)
      .mockResolvedValueOnce(
        jsonResponse(200, {
          messages: [searchHit('message-latest', 2)],
          total_matches: 1,
          next_cursor: null,
          has_more: false,
        }),
      )
    vi.stubGlobal('fetch', fetchMock)
    const search = useConversationSearch({
      token: 'jwt-token',
      conversationId: 'conversation-1',
      query,
    })
    const staleSignal = (fetchMock.mock.calls[0]?.[1] as RequestInit | undefined)?.signal

    query.value = 'cronograma'
    await flushPromises()

    expect(fetchMock).toHaveBeenCalledOnce()
    expect(staleSignal?.aborted).toBe(false)

    await vi.advanceTimersByTimeAsync(800)
    await flushPromises()

    expect(staleSignal?.aborted).toBe(true)
    expect(search.activeHit.value?.message.id).toBe('message-latest')

    staleResponse.resolve(
      jsonResponse(200, {
        messages: [searchHit('message-stale', 1)],
        total_matches: 1,
        next_cursor: null,
        has_more: false,
      }),
    )
    await flushPromises()

    expect(search.activeHit.value?.message.id).toBe('message-latest')
  })

  it('exposes unexpected request failures', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('Falha de rede')))
    const search = useConversationSearch({
      token: 'jwt-token',
      conversationId: 'conversation-1',
      query: 'agenda',
    })

    await flushPromises()

    expect(search.status.value).toBe('error')
    expect(search.error.value).toBe('Não foi possível conectar ao servidor.')
    expect(search.matches.value).toEqual([])
  })
})

function searchHit(id: string, position: number) {
  return {
    id,
    conversation_id: 'conversation-1',
    body: 'Agenda atualizada',
    inserted_at: '2026-07-22T11:02:44.884210Z',
    sender: {
      id: 'user-ana',
      username: 'ana',
      name: 'Ana Beatriz',
      last_seen_at: null,
      online: false,
    },
    position,
    match_offsets: [{ start: 0, length: 6 }],
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise
  })

  return { promise, resolve }
}
