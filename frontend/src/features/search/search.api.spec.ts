import { afterEach, describe, expect, it, vi } from 'vitest'

import { jsonResponse } from '@/test/http'

import { searchConversationMessages } from './search.api'

describe('search.api', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('searches conversation messages with the documented request and response shape', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        messages: [
          {
            ...messageResponse('message-1', 'Ajustei o cronograma final'),
            position: 1,
            match_offsets: [{ start: 10, length: 10 }],
          },
        ],
        total_matches: 1,
        next_cursor: null,
        has_more: false,
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const result = await searchConversationMessages('conversation-ana', 'cronograma final', 'jwt-token')

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/conversation-ana/messages/search?q=cronograma+final&limit=100',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(result).toEqual({
      matches: [
        {
          message: {
            id: 'message-1',
            conversationId: 'conversation-ana',
            body: 'Ajustei o cronograma final',
            insertedAt: '2026-07-22T11:02:44.884210Z',
            sender: {
              id: 'user-ana',
              username: 'anabeatriz',
              name: 'Ana Beatriz',
              lastSeenAt: null,
              online: false,
            },
          },
          position: 1,
          matchOffsets: [{ start: 10, length: 10 }],
        },
      ],
      totalMatches: 1,
      truncated: false,
    })
  })

  it('preserves search validation errors for the UI', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(422, {
          errors: {
            code: 'validation_error',
            detail: 'The request could not be processed',
            fields: {
              q: ['must be at least 2 characters'],
            },
          },
        }),
      ),
    )

    await expect(searchConversationMessages('conversation-ana', 'a', 'jwt-token')).rejects.toMatchObject({
      code: 'validation_error',
      status: 422,
      fields: {
        q: ['must be at least 2 characters'],
      },
    })
  })
})

function messageResponse(id: string, body: string) {
  return {
    id,
    conversation_id: 'conversation-ana',
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
