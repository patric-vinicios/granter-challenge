import { afterEach, describe, expect, it, vi } from 'vitest'

import {
  addGroupMembers,
  createGroupConversation,
  leaveGroup,
  openPrivateConversation,
  removeGroupMember,
} from './conversations.api'

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

  it('creates a group with the documented body and decodes members', async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(201, { conversation: groupResponse() }))
    vi.stubGlobal('fetch', fetchMock)

    const conversation = await createGroupConversation('Time de Produto', ['user-ana', 'user-carlos'], 'jwt-token')

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/groups',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ name: 'Time de Produto', member_ids: ['user-ana', 'user-carlos'] }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
          'Content-Type': 'application/json',
        }),
      }),
    )
    expect(conversation).toMatchObject({
      id: 'group-product',
      type: 'group',
      name: 'Time de Produto',
      creatorId: 'user-current',
      memberCount: 3,
    })
  })

  it('adds members and preserves group error codes', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(200, { conversation: groupResponse({ memberCount: 4 }) }))
      .mockResolvedValueOnce(
        jsonResponse(409, {
          errors: {
            code: 'already_member',
            detail: 'This user is already a member of the group',
          },
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    await addGroupMembers('group-product', ['user-leticia'], 'jwt-token')

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/group-product/members',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ member_ids: ['user-leticia'] }),
      }),
    )
    await expect(addGroupMembers('group-product', ['user-ana'], 'jwt-token')).rejects.toMatchObject({
      code: 'already_member',
      status: 409,
    })
  })

  it('uses the executable DELETE contracts for remove and leave', async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(204, null))
    vi.stubGlobal('fetch', fetchMock)

    await removeGroupMember('group-product', 'user-ana', 'jwt-token')
    await leaveGroup('group-product', 'jwt-token')

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      'http://localhost:4000/api/conversations/group-product/members/user-ana',
      expect.objectContaining({ method: 'DELETE' }),
    )
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      'http://localhost:4000/api/conversations/group-product/members/me',
      expect.objectContaining({ method: 'DELETE' }),
    )
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

function groupResponse(overrides: { memberCount?: number } = {}) {
  return {
    id: 'group-product',
    type: 'group',
    name: 'Time de Produto',
    creator_id: 'user-current',
    member_count: overrides.memberCount ?? 3,
    last_read_at: null,
    members: [
      userResponse('user-current', 'patric', 'Patric'),
      userResponse('user-ana', 'anabeatriz', 'Ana Beatriz'),
      userResponse('user-carlos', 'carlos', 'Carlos Silva'),
    ],
  }
}

function userResponse(id: string, username: string, name: string) {
  return {
    id,
    username,
    name,
    last_seen_at: null,
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
