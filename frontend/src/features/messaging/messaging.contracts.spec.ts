import { describe, expect, it } from 'vitest'

import {
  decodeConversationUpdated,
  decodeMembershipRevoked,
  decodeMessageAck,
  decodeMessageSendError,
  decodePersistedMessage,
} from './messaging.contracts'

describe('messaging contracts', () => {
  it('decodes the canonical message payload used by history, ack, and broadcast', () => {
    expect(decodePersistedMessage(messagePayload())).toEqual({
      id: 'message-1',
      conversationId: 'conversation-1',
      body: 'bom dia',
      insertedAt: '2026-07-23T17:40:00.000000Z',
      sender: {
        id: 'user-1',
        username: 'ana',
        name: 'Ana Beatriz',
        lastSeenAt: null,
      },
    })
  })

  it('decodes success and error replies with echoed client_ref', () => {
    expect(
      decodeMessageAck({
        message: messagePayload(),
        client_ref: 'client-1',
      }),
    ).toMatchObject({
      clientRef: 'client-1',
      message: {
        id: 'message-1',
      },
    })

    expect(
      decodeMessageSendError({
        reason: 'validation_error',
        fields: { body: ["can't be blank"] },
        client_ref: 'client-1',
      }),
    ).toEqual({
      reason: 'validation_error',
      fields: { body: ["can't be blank"] },
      clientRef: 'client-1',
      retryAfterMs: undefined,
    })
  })

  it('decodes personal topic and membership revocation events', () => {
    expect(
      decodeConversationUpdated({
        conversation_id: 'conversation-1',
        last_message: {
          preview: 'bom dia',
          sender_id: 'user-1',
          inserted_at: '2026-07-23T17:40:00.000000Z',
        },
        unread: true,
      }),
    ).toEqual({
      conversationId: 'conversation-1',
      lastMessage: {
        preview: 'bom dia',
        senderId: 'user-1',
        insertedAt: '2026-07-23T17:40:00.000000Z',
      },
      unread: true,
    })

    expect(decodeMembershipRevoked({ conversation_id: 'conversation-1' })).toEqual({
      conversationId: 'conversation-1',
    })
  })

  it('rejects unsupported payloads before they drive UI state', () => {
    expect(() => decodeMessageSendError({ reason: 'typing' })).toThrow('Unsupported message send error')
    expect(() => decodeConversationUpdated({ conversation_id: 'conversation-1' })).toThrow('Expected object')
  })
})

function messagePayload() {
  return {
    id: 'message-1',
    conversation_id: 'conversation-1',
    body: 'bom dia',
    inserted_at: '2026-07-23T17:40:00.000000Z',
    sender: {
      id: 'user-1',
      username: 'ana',
      name: 'Ana Beatriz',
      last_seen_at: null,
    },
  }
}
