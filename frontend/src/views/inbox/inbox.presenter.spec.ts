import { describe, expect, it } from 'vitest'

import type { InboxConversationSummary } from '@/features/conversations/conversations.contracts'
import type { ChatConversation } from '@/types/chat'
import type { PersistedMessage } from '@/types/message'

import {
  inboxPreview,
  toInboxConversationItem,
  unreadLabel,
  withActiveSearchHit,
  type InboxPresenterContext,
} from './inbox.presenter'

const currentUserId = 'user-current'
const sender = {
  id: 'user-ana',
  username: 'ana',
  name: 'Ana Beatriz',
  lastSeenAt: null,
  online: false,
}
const context: InboxPresenterContext = {
  currentUserId,
  histories: {},
  initialsFor: (name) => name.slice(0, 2).toUpperCase(),
  presenceSubtitleFor: () => 'offline',
}

describe('inbox presenter', () => {
  it('preserves own-message preview and unread overflow labels', () => {
    const summary: InboxConversationSummary = {
      id: 'group-product',
      type: 'group',
      title: 'Time de Produto',
      counterpart: null,
      memberCount: 3,
      lastMessage: {
        id: 'message-1',
        body: 'Combinado',
        senderId: currentUserId,
        insertedAt: '2026-07-22T09:42:00',
      },
      unreadCount: 100,
      unreadOverflow: true,
      lastReadAt: null,
    }

    expect(inboxPreview(summary, currentUserId)).toBe('Voce: Combinado')
    expect(unreadLabel(summary)).toBe('99+')
    expect(toInboxConversationItem(summary, context)).toMatchObject({
      subtitle: '3 membros',
      preview: 'Voce: Combinado',
      time: '09:42',
      unreadLabel: '99+',
    })
  })

  it('appends an active search hit once', () => {
    const conversation: ChatConversation = {
      id: 'conversation-ana',
      type: 'private',
      initials: 'AB',
      name: 'Ana Beatriz',
      subtitle: 'offline',
      preview: '',
      time: '',
      messages: [],
    }
    const hit = {
      message: messageWithBody('Resultado da busca'),
      position: 1,
      matchOffsets: [{ start: 0, length: 9 }],
    }
    const withHit = withActiveSearchHit(conversation, hit, currentUserId)

    expect(withHit.messages).toHaveLength(1)
    expect(withActiveSearchHit(withHit, hit, currentUserId)).toBe(withHit)
  })
})

function messageWithBody(body: string): PersistedMessage {
  return {
    id: 'message-search',
    conversationId: 'conversation-ana',
    body,
    insertedAt: '2026-07-22T09:42:00',
    sender,
  }
}
