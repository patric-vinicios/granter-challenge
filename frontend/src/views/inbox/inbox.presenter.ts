import type { ContactUser } from '@/features/contacts/contacts.contracts'
import type {
  ConversationRecord,
  InboxConversationSummary,
} from '@/features/conversations/conversations.contracts'
import type { Conversation, Message } from '@/features/conversations/conversations.mock'
import type { PersistedMessage } from '@/features/messaging/messaging.contracts'
import type { ConversationSearchHit } from '@/features/search/search.contracts'
import { formatMessageTime } from '@/shared/date/formatMessageTime'

interface ConversationHistory {
  messages: readonly PersistedMessage[]
}

export interface InboxPresenterContext {
  currentUserId: string | null
  histories: Readonly<Record<string, ConversationHistory>>
  initialsFor: (name: string) => string
  presenceSubtitleFor: (user: ContactUser) => string
}

export function toConversationItem(
  conversation: ConversationRecord,
  context: InboxPresenterContext,
): Conversation {
  const messages =
    context.histories[conversation.id]?.messages.map((message) =>
      toMessageItem(message, context.currentUserId),
    ) ?? []

  if (conversation.type === 'private') {
    return {
      id: conversation.id,
      type: conversation.type,
      initials: context.initialsFor(conversation.counterpart.name),
      name: conversation.counterpart.name,
      subtitle: context.presenceSubtitleFor(conversation.counterpart),
      preview: 'Conversa iniciada',
      time: '',
      messages,
    }
  }

  return {
    id: conversation.id,
    type: conversation.type,
    initials: context.initialsFor(conversation.name),
    name: conversation.name,
    subtitle: `${conversation.memberCount} membros`,
    preview: 'Grupo criado',
    time: '',
    messages,
  }
}

export function toInboxConversationItem(
  conversation: InboxConversationSummary,
  context: InboxPresenterContext,
): Conversation & { unreadLabel?: string } {
  const messages =
    context.histories[conversation.id]?.messages.map((message) =>
      toMessageItem(message, context.currentUserId),
    ) ?? []

  return {
    id: conversation.id,
    type: conversation.type,
    initials: context.initialsFor(conversation.title),
    name: conversation.title,
    subtitle:
      conversation.type === 'group'
        ? `${conversation.memberCount ?? 0} membros`
        : conversation.counterpart
          ? context.presenceSubtitleFor(conversation.counterpart)
          : 'offline',
    preview: inboxPreview(conversation, context.currentUserId),
    time: conversation.lastMessage ? formatMessageTime(conversation.lastMessage.insertedAt) : '',
    messages,
    unreadLabel: unreadLabel(conversation),
  }
}

export function inboxPreview(
  conversation: InboxConversationSummary,
  currentUserId: string | null,
): string {
  const message = conversation.lastMessage

  if (!message) {
    return 'Nenhuma mensagem'
  }

  const prefix = message.senderId === currentUserId ? 'Voce: ' : ''

  return `${prefix}${message.body}`
}

export function unreadLabel(conversation: InboxConversationSummary): string | undefined {
  if (conversation.unreadCount <= 0) {
    return undefined
  }

  return conversation.unreadOverflow ? '99+' : String(conversation.unreadCount)
}

export function toMessageItem(
  message: PersistedMessage,
  currentUserId: string | null,
): Message {
  return {
    id: message.id,
    side: message.sender.id === currentUserId ? 'out' : 'in',
    author: message.sender.id === currentUserId ? undefined : message.sender.name,
    text: message.body,
    time: formatMessageTime(message.insertedAt),
    wide: message.body.length > 44,
  }
}

export function withActiveSearchHit(
  conversation: Conversation,
  hit: ConversationSearchHit | null,
  currentUserId: string | null,
): Conversation {
  if (!hit || hit.message.conversationId !== conversation.id) {
    return conversation
  }

  if (conversation.messages.some((message) => message.id === hit.message.id)) {
    return conversation
  }

  return {
    ...conversation,
    messages: [...conversation.messages, toMessageItem(hit.message, currentUserId)],
  }
}
