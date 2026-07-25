import { afterEach, describe, expect, it, vi } from 'vitest'

import { jsonResponse } from '@/test/http'

import { listMessages } from './messaging.api'

describe('messaging.api', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('loads conversation history through the documented endpoint', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        messages: [
          messageResponse({
            id: 'message-1',
            body: 'bom dia',
            insertedAt: '2026-07-22T13:48:17.123456Z',
          }),
        ],
        next_cursor: 'older-cursor',
        has_more: true,
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    await expect(listMessages('conversation-1', 'jwt-token', { before: 'cursor atual', limit: 30 })).resolves.toEqual({
      messages: [
        {
          id: 'message-1',
          conversationId: 'conversation-1',
          body: 'bom dia',
          insertedAt: '2026-07-22T13:48:17.123456Z',
          sender: {
            id: 'user-ana',
            username: 'anabeatriz',
            name: 'Ana Beatriz',
            lastSeenAt: null,
            online: false,
          },
        },
      ],
      nextCursor: 'older-cursor',
      hasMore: true,
    })

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/conversation-1/messages?limit=30&before=cursor+atual',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
  })

  it('preserves message history error codes for UI decisions', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(400, {
          errors: {
            code: 'invalid_cursor',
            detail: 'The pagination cursor is invalid',
          },
        }),
      ),
    )

    await expect(listMessages('conversation-1', 'jwt-token', { before: 'tampered' })).rejects.toMatchObject({
      code: 'invalid_cursor',
      status: 400,
      message: 'O cursor de paginação é inválido.',
    })
  })

  it('rejects invalid response payloads at the transport boundary', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          messages: [{ id: 'message-1' }],
          next_cursor: null,
          has_more: false,
        }),
      ),
    )

    await expect(listMessages('conversation-1', 'jwt-token')).rejects.toMatchObject({
      code: 'invalid_response',
    })
  })
})

function messageResponse(options: { id: string; body: string; insertedAt: string }) {
  return {
    id: options.id,
    conversation_id: 'conversation-1',
    body: options.body,
    inserted_at: options.insertedAt,
    sender: {
      id: 'user-ana',
      username: 'anabeatriz',
      name: 'Ana Beatriz',
      last_seen_at: null,
    },
  }
}
