import { describe, expect, it } from 'vitest'

import {
  decodeConversation,
  decodeInboxConversations,
  decodeMarkReadResult,
} from './conversations.contracts'

describe('conversation contracts', () => {
  it('decodes private and group conversations', () => {
    expect(
      decodeConversation({
        conversation: {
          id: 'private-1',
          type: 'private',
          last_read_at: null,
          counterpart: userResponse(),
        },
      }),
    ).toMatchObject({ id: 'private-1', type: 'private', counterpart: { online: false } })

    expect(
      decodeConversation({
        conversation: {
          id: 'group-1',
          type: 'group',
          name: 'Produto',
          creator_id: 'user-current',
          member_count: 1,
          members: [userResponse({ online: true })],
        },
      }),
    ).toMatchObject({
      id: 'group-1',
      type: 'group',
      lastReadAt: null,
      members: [{ online: true }],
    })
  })

  it('decodes nullable inbox summary fields and last messages', () => {
    expect(
      decodeInboxConversations({
        conversations: [
          summaryResponse(),
          {
            ...summaryResponse(),
            id: 'group-1',
            type: 'group',
            counterpart: null,
            member_count: 3,
            last_message: null,
          },
        ],
      }),
    ).toMatchObject([
      { id: 'private-1', lastMessage: { senderId: 'user-1' } },
      { id: 'group-1', counterpart: null, memberCount: 3, lastMessage: null },
    ])
  })

  it('decodes only the canonical zero-unread mark-read result', () => {
    expect(
      decodeMarkReadResult({
        conversation_id: 'private-1',
        last_read_at: '2026-07-24T10:00:00Z',
        unread_count: 0,
      }),
    ).toEqual({
      conversationId: 'private-1',
      lastReadAt: '2026-07-24T10:00:00Z',
      unreadCount: 0,
    })

    expect(() =>
      decodeMarkReadResult({
        conversation_id: 'private-1',
        last_read_at: '2026-07-24T10:00:00Z',
        unread_count: 1,
      }),
    ).toThrow('Expected zero')
  })

  it.each([
    null,
    { conversation: { id: 'x', type: 'channel' } },
    {
      conversation: {
        id: 'group-1',
        type: 'group',
        name: 'Produto',
        creator_id: 'user-current',
        member_count: Number.NaN,
        members: [],
      },
    },
    {
      conversation: {
        id: 'group-1',
        type: 'group',
        name: 'Produto',
        creator_id: 'user-current',
        member_count: 1,
        members: {},
      },
    },
  ])('rejects malformed conversation records %#', (payload) => {
    expect(() => decodeConversation(payload)).toThrow()
  })

  it.each([
    null,
    {},
    { conversations: {} },
    { conversations: [{ ...summaryResponse(), type: 'channel' }] },
    { conversations: [{ ...summaryResponse(), unread_overflow: 'false' }] },
    { conversations: [{ ...summaryResponse(), member_count: '1' }] },
    { conversations: [{ ...summaryResponse(), last_message: { body: 'missing fields' } }] },
  ])('rejects malformed inbox summaries %#', (payload) => {
    expect(() => decodeInboxConversations(payload)).toThrow()
  })
})

function userResponse(overrides: Record<string, unknown> = {}) {
  return {
    id: 'user-1',
    username: 'ana',
    name: 'Ana',
    last_seen_at: null,
    ...overrides,
  }
}

function summaryResponse() {
  return {
    id: 'private-1',
    type: 'private',
    title: 'Ana',
    counterpart: userResponse(),
    member_count: null,
    last_message: {
      id: 'message-1',
      body: 'Oi',
      sender_id: 'user-1',
      inserted_at: '2026-07-24T10:00:00Z',
    },
    unread_count: 2,
    unread_overflow: false,
    last_read_at: null,
  }
}
