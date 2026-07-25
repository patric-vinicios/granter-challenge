import { describe, expect, it } from 'vitest'

import type { InboxConversationSummary } from '@/features/conversations/conversations.contracts'
import type { ChatConversation } from '@/types/chat'
import type { PersistedMessage } from '@/types/message'

import {
  inboxPreview,
  toInboxConversationItem,
  toMessageItem,
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

  it('marks persisted messages as wide only above 44 characters', () => {
    expect(toMessageItem(messageWithBody('a'.repeat(44)), currentUserId).wide).toBe(false)
    expect(toMessageItem(messageWithBody('a'.repeat(45)), currentUserId).wide).toBe(true)
  })

  it('injects an active search hit once', () => {
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

  it('positions a far active search hit by its original message date', () => {
    const conversation: ChatConversation = {
      id: 'conversation-ana',
      type: 'private',
      initials: 'AB',
      name: 'Ana Beatriz',
      subtitle: 'offline',
      preview: '',
      time: '',
      messages: [
        {
          id: 'message-499',
          side: 'in',
          text: 'Mensagem atual 499',
          time: '10:00',
          insertedAt: '2026-07-22T10:00:00Z',
        },
        {
          id: 'message-500',
          side: 'in',
          text: 'Mensagem atual 500',
          time: '10:01',
          insertedAt: '2026-07-22T10:01:00Z',
        },
      ],
    }
    const hit = {
      message: messageWithBody('Resultado antigo fora da pagina atual', '2026-07-21T09:42:00Z'),
      position: 4500,
      matchOffsets: [{ start: 0, length: 9 }],
    }

    expect(withActiveSearchHit(conversation, hit, currentUserId).messages.map((message) => message.id)).toEqual([
      'message-search',
      'message-499',
      'message-500',
    ])
  })
})

function messageWithBody(body: string, insertedAt = '2026-07-22T09:42:00'): PersistedMessage {
  return {
    id: 'message-search',
    conversationId: 'conversation-ana',
    body,
    insertedAt,
    sender,
  }
}
