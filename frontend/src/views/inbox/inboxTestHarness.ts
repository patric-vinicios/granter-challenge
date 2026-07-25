import { vi } from 'vitest'

import { useAuthStore } from '@/stores/auth.store'
import { jsonResponse } from '@/test/http'
import { renderWithApp } from '@/test/render'
import { FakeSocket } from '@/test/realtime'

import InboxView from '../InboxView.vue'

export const sockets: FakeSocket[] = []

vi.mock('@/shared/realtime/socket', () => ({
  createRealtimeSocket: (token: string) => {
    const socket = new FakeSocket(token)
    sockets.push(socket)
    return socket
  },
}))

const routes = [
  {
    path: '/',
    component: { template: '<div>Login</div>' },
  },
  {
    path: '/inbox',
    component: InboxView,
  },
]

export async function renderInbox(initialRoute = '/inbox') {
  return renderWithApp(InboxView, { routes, initialRoute })
}

export function resetInboxHarness(): void {
  sockets.length = 0
}

export function authenticate(pinia: Awaited<ReturnType<typeof renderInbox>>['pinia']) {
  const auth = useAuthStore(pinia)
  auth.user = {
    id: 'user-current',
    username: 'patric',
    name: 'Patric',
    lastSeenAt: null,
  }
  auth.token = 'jwt-token'
  auth.expiresAt = '2026-07-30T12:00:00Z'
}

export function contactResponse(id: string, userId: string, username: string, name: string) {
  return {
    id,
    user: {
      id: userId,
      username,
      name,
      last_seen_at: null,
      online: false,
    },
  }
}

export function inboxSummaryResponse(
  options: {
    id: string
    title: string
    senderId: string
    body: string
    unreadCount: number
    type?: 'private' | 'group'
    unreadOverflow?: boolean
    memberCount?: number
    lastSeenAt?: string | null
    online?: boolean
  },
) {
  return {
    id: options.id,
    type: options.type ?? 'private',
    title: options.title,
    counterpart:
      options.type === 'group'
        ? null
        : {
            id: 'user-ana',
            username: 'anabeatriz',
            name: options.title,
            last_seen_at: options.lastSeenAt ?? null,
            online: options.online ?? false,
          },
    member_count: options.type === 'group' ? (options.memberCount ?? 3) : null,
    last_message: {
      id: `message-${options.id}`,
      body: options.body,
      sender_id: options.senderId,
      inserted_at: '2026-07-22T11:02:44.884210Z',
    },
    unread_count: options.unreadCount,
    unread_overflow: options.unreadOverflow ?? false,
    last_read_at: null,
  }
}

export function defaultAnaInboxSummary() {
  return inboxSummaryResponse({
    id: 'ana',
    title: 'Ana Beatriz',
    senderId: 'user-ana',
    body: 'Perfeito, fico no aguardo entao',
    unreadCount: 0,
  })
}

export function privateConversationResponse(id: string, userId: string, username: string, name: string) {
  return {
    id,
    type: 'private',
    last_read_at: null,
    counterpart: {
      id: userId,
      username,
      name,
      last_seen_at: null,
      online: false,
    },
  }
}

export function groupResponse(options: { includeAna?: boolean; includeLeticia?: boolean } = {}) {
  const includeAna = options.includeAna ?? true
  const members = [
    userResponse('user-current', 'patric', 'Patric'),
    ...(includeAna ? [userResponse('user-ana', 'anabeatriz', 'Ana Beatriz')] : []),
    userResponse('user-carlos', 'carlos', 'Carlos Silva'),
    ...(options.includeLeticia ? [userResponse('user-leticia', 'leticia', 'Leticia Moraes')] : []),
  ]

  return {
    id: 'group-product',
    type: 'group',
    name: 'Time de Produto',
    creator_id: 'user-current',
    member_count: members.length,
    last_read_at: null,
    members,
  }
}

function userResponse(id: string, username: string, name: string) {
  return {
    id,
    username,
    name,
    last_seen_at: null,
    online: false,
  }
}

export function historyResponse(
  options: {
    messages?: ReturnType<typeof historyMessageResponse>[]
    nextCursor?: string | null
    hasMore?: boolean
  } = {},
) {
  return jsonResponse(200, {
    messages: options.messages ?? [],
    next_cursor: options.nextCursor ?? null,
    has_more: options.hasMore ?? false,
  })
}

export function historyMessageResponse(id: string, body: string, senderId: string, senderName: string, insertedAt: string) {
  return {
    id,
    conversation_id: 'conversation-ana',
    body,
    inserted_at: insertedAt,
    sender: {
      id: senderId,
      username: senderName.toLowerCase().replaceAll(' ', ''),
      name: senderName,
      last_seen_at: null,
      online: false,
    },
  }
}

export { jsonResponse } from '@/test/http'

export function mockAuthenticatedFetch(options: {
  contacts?: unknown[]
  conversations?: unknown[]
  filteredConversations?: unknown[]
  historyMessages?: unknown[]
  historyResponses?: unknown[][]
  conversationDetails?: unknown
  searchResult?: unknown
}) {
  const conversations = options.conversations ?? []
  const filteredConversations = options.filteredConversations ?? conversations
  let historyResponseIndex = 0

  const fetchMock = vi.fn((url: string | URL | Request, init?: RequestInit) => {
    const href = typeof url === 'string' ? url : url instanceof URL ? url.href : url.url
    const method = init?.method ?? 'GET'

    if (href === 'http://localhost:4000/api/contacts' && method === 'GET') {
      return Promise.resolve(jsonResponse(200, { contacts: options.contacts ?? [] }))
    }

    if (href === 'http://localhost:4000/api/conversations' && method === 'GET') {
      return Promise.resolve(jsonResponse(200, { conversations }))
    }

    if (href.startsWith('http://localhost:4000/api/conversations?q=') && method === 'GET') {
      return Promise.resolve(jsonResponse(200, { conversations: filteredConversations }))
    }

    if (href === 'http://localhost:4000/api/conversations/group-product' && method === 'GET') {
      return Promise.resolve(jsonResponse(200, { conversation: options.conversationDetails ?? groupResponse() }))
    }

    if (href.startsWith('http://localhost:4000/api/conversations/ana/messages/search?') && method === 'GET') {
      return Promise.resolve(
        jsonResponse(
          200,
          options.searchResult ?? {
            messages: [],
            total_matches: 0,
            next_cursor: null,
            has_more: false,
          },
        ),
      )
    }

    if (
      href.startsWith('http://localhost:4000/api/conversations/') &&
      href.includes('/messages?') &&
      method === 'GET'
    ) {
      const messages =
        options.historyResponses?.[historyResponseIndex++] ?? options.historyMessages ?? []

      return Promise.resolve(
        jsonResponse(200, {
          messages,
          next_cursor: null,
          has_more: false,
        }),
      )
    }

    if (
      href.startsWith('http://localhost:4000/api/conversations/') &&
      href.endsWith('/read') &&
      method === 'POST'
    ) {
      const conversationId = href.split('/').at(-2) ?? ''

      return Promise.resolve(
        jsonResponse(200, {
          conversation_id: conversationId,
          last_read_at: '2026-07-24T18:00:01Z',
          unread_count: 0,
        }),
      )
    }

    return Promise.resolve(
      jsonResponse(500, {
        errors: {
          code: 'unexpected_test_request',
          detail: `Unexpected test request: ${method} ${href}`,
        },
      }),
    )
  })

  return fetchMock
}

export function searchHitResponse(
  id: string,
  body: string,
  position: number,
  matchOffsets: Array<{ start: number; length: number }>,
) {
  return {
    ...realtimeMessageResponse({
      id,
      body,
      senderId: 'user-ana',
      senderName: 'Ana Beatriz',
    }),
    position,
    match_offsets: matchOffsets,
  }
}

export function realtimeMessageResponse({
  id,
  body,
  senderId,
  senderName,
}: {
  id: string
  body: string
  senderId: string
  senderName: string
}) {
  return {
    id,
    conversation_id: 'ana',
    body,
    inserted_at: '2026-07-23T17:40:00.000000Z',
    sender: {
      id: senderId,
      username: senderName.toLowerCase().replaceAll(' ', ''),
      name: senderName,
      last_seen_at: null,
      online: false,
    },
  }
}
