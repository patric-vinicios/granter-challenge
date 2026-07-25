import { describe, expect, it } from 'vitest'

import type { PersistedMessage } from '@/types/message'

import { toChatMessage } from './toChatMessage'

const message: PersistedMessage = {
  id: 'message-1',
  conversationId: 'conversation-1',
  body: 'Olá',
  insertedAt: '2026-07-22T09:42:00',
  sender: {
    id: 'user-ana',
    username: 'anabeatriz',
    name: 'Ana Beatriz',
    lastSeenAt: null,
    online: false,
  },
}

describe('toChatMessage', () => {
  it('maps an incoming persisted message for presentation', () => {
    expect(toChatMessage(message, 'user-current')).toEqual({
      id: 'message-1',
      side: 'in',
      author: 'Ana Beatriz',
      text: 'Olá',
      time: '09:42',
    })
  })

  it('omits the author for the current user', () => {
    expect(toChatMessage(message, 'user-ana')).toMatchObject({
      side: 'out',
      author: undefined,
    })
  })
})
