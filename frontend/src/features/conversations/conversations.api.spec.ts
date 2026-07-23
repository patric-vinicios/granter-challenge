import { afterEach, describe, expect, it, vi } from 'vitest'

import { openPrivateConversation } from './conversations.api'

describe('conversations.api', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('opens a private conversation with the documented request and response shape', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(201, {
        conversation: privateConversationResponse('conversation-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const conversation = await openPrivateConversation('user-ana', 'jwt-token')

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/private',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ user_id: 'user-ana' }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
          'Content-Type': 'application/json',
        }),
      }),
    )
    expect(conversation).toEqual({
      id: 'conversation-ana',
      type: 'private',
      lastReadAt: null,
      counterpart: {
        id: 'user-ana',
        username: 'anabeatriz',
        name: 'Ana Beatriz',
        lastSeenAt: null,
      },
    })
  })

  it('preserves private conversation error codes for UI decisions', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(403, {
          errors: {
            code: 'not_a_contact',
            detail: 'You can only start conversations with your contacts',
          },
        }),
      ),
    )

    await expect(openPrivateConversation('user-stranger', 'jwt-token')).rejects.toMatchObject({
      code: 'not_a_contact',
      status: 403,
    })
  })
})

function privateConversationResponse(id: string, userId: string, username: string, name: string) {
  return {
    id,
    type: 'private',
    last_read_at: null,
    counterpart: {
      id: userId,
      username,
      name,
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
