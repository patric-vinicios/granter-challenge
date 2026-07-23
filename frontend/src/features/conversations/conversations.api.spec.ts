import { afterEach, describe, expect, it, vi } from 'vitest'

import {
  addGroupMembers,
  createGroupConversation,
  leaveGroup,
  listInboxConversations,
  markConversationRead,
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
        online: false,
      },
    })
  })

  it('lists inbox summaries with the documented response shape', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        conversations: [
          {
            id: 'conversation-ana',
            type: 'private',
            title: 'Ana Beatriz',
            counterpart: userResponse('user-ana', 'anabeatriz', 'Ana Beatriz'),
            member_count: null,
            last_message: {
              id: 'message-latest',
              body: 'bom dia!',
              sender_id: 'user-ana',
              inserted_at: '2026-07-22T11:02:44.884210Z',
            },
            unread_count: 3,
            unread_overflow: false,
            last_read_at: null,
          },
          {
            id: 'group-product',
            type: 'group',
            title: 'Time de Produto',
            counterpart: null,
            member_count: 7,
            last_message: null,
            unread_count: 99,
            unread_overflow: true,
            last_read_at: '2026-07-22T09:14:02.000000Z',
          },
        ],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const summaries = await listInboxConversations('jwt-token')

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(summaries).toEqual([
      {
        id: 'conversation-ana',
        type: 'private',
        title: 'Ana Beatriz',
        counterpart: {
          id: 'user-ana',
          username: 'anabeatriz',
          name: 'Ana Beatriz',
          lastSeenAt: null,
          online: false,
        },
        memberCount: null,
        lastMessage: {
          id: 'message-latest',
          body: 'bom dia!',
          senderId: 'user-ana',
          insertedAt: '2026-07-22T11:02:44.884210Z',
        },
        unreadCount: 3,
        unreadOverflow: false,
        lastReadAt: null,
      },
      {
        id: 'group-product',
        type: 'group',
        title: 'Time de Produto',
        counterpart: null,
        memberCount: 7,
        lastMessage: null,
        unreadCount: 99,
        unreadOverflow: true,
        lastReadAt: '2026-07-22T09:14:02.000000Z',
      },
    ])
  })

  it('filters inbox summaries with the documented query parameter', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        conversations: [
          {
            id: 'conversation-ana',
            type: 'private',
            title: 'Ana Beatriz',
            counterpart: userResponse('user-ana', 'anabeatriz', 'Ana Beatriz'),
            member_count: null,
            last_message: null,
            unread_count: 0,
            unread_overflow: false,
            last_read_at: null,
          },
        ],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const summaries = await listInboxConversations('jwt-token', { query: ' ana ' })

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations?q=ana',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(summaries).toHaveLength(1)
  })

  it('marks a conversation as read with the documented path and response shape', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        conversation_id: 'conversation-ana',
        last_read_at: '2026-07-22T14:30:11.204518Z',
        unread_count: 0,
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const result = await markConversationRead('conversation-ana', 'jwt-token')

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/conversation-ana/read',
      expect.objectContaining({
        method: 'POST',
        body: undefined,
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(result).toEqual({
      conversationId: 'conversation-ana',
      lastReadAt: '2026-07-22T14:30:11.204518Z',
      unreadCount: 0,
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
