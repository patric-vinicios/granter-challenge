import type { Page, Route, WebSocketRoute } from '@playwright/test'

interface UserResponse {
  id: string
  username: string
  name: string
  last_seen_at: string | null
  online: boolean
}

interface ContactResponse {
  id: string
  user: UserResponse
}

interface InboxSummaryResponse {
  id: string
  type: 'private' | 'group'
  title: string
  counterpart: UserResponse | null
  member_count: number | null
  last_message: {
    id: string
    body: string
    sender_id: string
    inserted_at: string
  } | null
  unread_count: number
  unread_overflow: boolean
  last_read_at: string | null
}

interface ConversationResponse {
  id: string
  type: 'private' | 'group'
  last_read_at: string | null
  counterpart?: UserResponse
  name?: string
  creator_id?: string
  member_count?: number
  members?: UserResponse[]
}

interface MessageResponse {
  id: string
  conversation_id: string
  body: string
  inserted_at: string
  sender: UserResponse
  position?: number
  match_offsets?: Array<{ start: number; length: number }>
}

interface CapturedRequest {
  method: string
  path: string
  body: unknown
}

export interface AppBackendState {
  contacts: ContactResponse[]
  conversations: InboxSummaryResponse[]
  conversationDetails: Record<string, ConversationResponse>
  histories: Record<string, MessageResponse[]>
  searches: Record<string, MessageResponse[]>
  nextContact: ContactResponse
  privateConversation: ConversationResponse
  sentMessages: MessageResponse[]
  requests: CapturedRequest[]
}

export function createBackendState(
  overrides: Partial<AppBackendState> = {},
): AppBackendState {
  return {
    contacts: [],
    conversations: [],
    conversationDetails: {},
    histories: {},
    searches: {},
    nextContact: contactResponse('contact-bruno', 'user-bruno', 'bruno', 'Bruno Lima'),
    privateConversation: privateConversationResponse(
      'conversation-bruno',
      userResponse('user-bruno', 'bruno', 'Bruno Lima'),
    ),
    sentMessages: [],
    requests: [],
    ...overrides,
  }
}

export async function installAppMocks(
  page: Page,
  state: AppBackendState,
): Promise<void> {
  await mockBackend(page, state)
  await mockRealtime(page, state)
}

async function installAuthenticatedSession(page: Page): Promise<void> {
  await page.addInitScript(() => {
    window.localStorage.setItem(
      'granter.session',
      JSON.stringify({
        user: {
          id: 'user-current',
          username: 'patric',
          name: 'Patric',
          lastSeenAt: null,
        },
        token: 'jwt-token',
        expiresAt: '2026-07-30T12:00:00Z',
      }),
    )
  })
}

export async function openAuthenticatedInbox(
  page: Page,
  state: AppBackendState,
): Promise<void> {
  await installAppMocks(page, state)
  await installAuthenticatedSession(page)
  await page.goto('/inbox')
}

function userResponse(
  id = 'user-current',
  username = 'patric',
  name = 'Patric',
): UserResponse {
  return {
    id,
    username,
    name,
    last_seen_at: null,
    online: id === 'user-current',
  }
}

export function contactResponse(
  id: string,
  userId: string,
  username: string,
  name: string,
): ContactResponse {
  return {
    id,
    user: userResponse(userId, username, name),
  }
}

function privateConversationResponse(
  id: string,
  counterpart: UserResponse,
): ConversationResponse {
  return {
    id,
    type: 'private',
    last_read_at: null,
    counterpart,
  }
}

export function inboxSummaryResponse(
  options: {
    id: string
    title: string
    body: string
    type?: 'private' | 'group'
    senderId?: string
    unreadCount?: number
  },
): InboxSummaryResponse {
  const type = options.type ?? 'private'
  const counterpart =
    type === 'private'
      ? userResponse('user-ana', 'ana', options.title)
      : null

  return {
    id: options.id,
    type,
    title: options.title,
    counterpart,
    member_count: type === 'group' ? 3 : null,
    last_message: {
      id: `last-${options.id}`,
      body: options.body,
      sender_id: options.senderId ?? 'user-ana',
      inserted_at: '2026-07-24T12:00:00.000Z',
    },
    unread_count: options.unreadCount ?? 0,
    unread_overflow: false,
    last_read_at: null,
  }
}

export function messageResponse(
  id: string,
  conversationId: string,
  body: string,
  sender = userResponse('user-ana', 'ana', 'Ana Beatriz'),
): MessageResponse {
  return {
    id,
    conversation_id: conversationId,
    body,
    inserted_at: '2026-07-24T12:00:00.000Z',
    sender,
  }
}

export function searchHitResponse(
  id: string,
  conversationId: string,
  body: string,
  position: number,
): MessageResponse {
  return {
    ...messageResponse(id, conversationId, body),
    position,
    match_offsets: [{ start: 0, length: Math.min(10, body.length) }],
  }
}

async function mockBackend(page: Page, state: AppBackendState): Promise<void> {
  await page.route('http://localhost:4000/api/**', async (route) => {
    const request = route.request()
    const url = new URL(request.url())
    const path = url.pathname
    const method = request.method()
    const body = request.postData() ? (request.postDataJSON() as unknown) : null
    state.requests.push({ method, path, body })

    if ((path === '/api/auth/login' || path === '/api/auth/register') && method === 'POST') {
      await fulfillJson(route, path.endsWith('register') ? 201 : 200, {
        user: userResponse(),
        token: 'jwt-token',
        expires_at: '2026-07-30T12:00:00Z',
      })
      return
    }

    if (path === '/api/auth/me' && method === 'GET') {
      await fulfillJson(route, 200, { user: userResponse() })
      return
    }

    if (path === '/api/contacts' && method === 'GET') {
      await fulfillJson(route, 200, { contacts: state.contacts })
      return
    }

    if (path === '/api/contacts' && method === 'POST') {
      if (!state.contacts.some((contact) => contact.id === state.nextContact.id)) {
        state.contacts.push(state.nextContact)
      }
      await fulfillJson(route, 201, { contact: state.nextContact })
      return
    }

    if (path.startsWith('/api/contacts/') && method === 'DELETE') {
      const contactId = decodeURIComponent(path.split('/').at(-1) ?? '')
      state.contacts = state.contacts.filter((contact) => contact.id !== contactId)
      await fulfillEmpty(route, 204)
      return
    }

    if (path === '/api/conversations' && method === 'GET') {
      const query = url.searchParams.get('q')?.toLocaleLowerCase().trim()
      const conversations = query
        ? state.conversations.filter((conversation) =>
            `${conversation.title} ${conversation.last_message?.body ?? ''}`
              .toLocaleLowerCase()
              .includes(query),
          )
        : state.conversations
      await fulfillJson(route, 200, { conversations })
      return
    }

    if (path === '/api/conversations/private' && method === 'POST') {
      await fulfillJson(route, 200, { conversation: state.privateConversation })
      return
    }

    if (path === '/api/conversations/groups' && method === 'POST') {
      const payload = requireRecord(body)
      const memberIds = Array.isArray(payload.member_ids)
        ? payload.member_ids.filter((id): id is string => typeof id === 'string')
        : []
      const members = [
        userResponse(),
        ...state.contacts
          .filter((contact) => memberIds.includes(contact.user.id))
          .map((contact) => contact.user),
      ]
      const conversation: ConversationResponse = {
        id: 'group-created',
        type: 'group',
        name: typeof payload.name === 'string' ? payload.name : 'Novo grupo',
        creator_id: 'user-current',
        member_count: members.length,
        last_read_at: null,
        members,
      }
      state.conversationDetails[conversation.id] = conversation
      await fulfillJson(route, 201, { conversation })
      return
    }

    const searchMatch = path.match(/^\/api\/conversations\/([^/]+)\/messages\/search$/)
    if (searchMatch && method === 'GET') {
      const conversationId = decodeURIComponent(searchMatch[1] ?? '')
      const matches = state.searches[conversationId] ?? []
      await fulfillJson(route, 200, {
        messages: matches,
        total_matches: matches.length,
        next_cursor: null,
        has_more: false,
      })
      return
    }

    const historyMatch = path.match(/^\/api\/conversations\/([^/]+)\/messages$/)
    if (historyMatch && method === 'GET') {
      const conversationId = decodeURIComponent(historyMatch[1] ?? '')
      await fulfillJson(route, 200, {
        messages: state.histories[conversationId] ?? [],
        next_cursor: null,
        has_more: false,
      })
      return
    }

    const readMatch = path.match(/^\/api\/conversations\/([^/]+)\/read$/)
    if (readMatch && method === 'POST') {
      await fulfillJson(route, 200, {
        conversation_id: decodeURIComponent(readMatch[1] ?? ''),
        last_read_at: '2026-07-24T12:05:00.000Z',
        unread_count: 0,
      })
      return
    }

    const detailsMatch = path.match(/^\/api\/conversations\/([^/]+)$/)
    if (detailsMatch && method === 'GET') {
      const conversationId = decodeURIComponent(detailsMatch[1] ?? '')
      const conversation = state.conversationDetails[conversationId]
      if (conversation) {
        await fulfillJson(route, 200, { conversation })
        return
      }
    }

    await fulfillJson(route, 500, {
      errors: {
        code: 'unexpected_e2e_request',
        detail: `Unexpected E2E request: ${method} ${path}`,
      },
    })
  })
}

async function mockRealtime(page: Page, state: AppBackendState): Promise<void> {
  await page.routeWebSocket('ws://localhost:4000/socket/**', (socket) => {
    socket.onMessage((rawMessage) => {
      const frame = decodePhoenixFrame(rawMessage)
      if (!frame) {
        return
      }

      const [joinRef, ref, topic, event, rawPayload] = frame

      if (event === 'phx_join' || event === 'heartbeat') {
        reply(socket, joinRef, ref, topic, {})
        return
      }

      if (event === 'new_message') {
        const payload = requireRecord(rawPayload)
        const conversationId = topic.replace(/^conversation:/, '')
        const message = messageResponse(
          `sent-${state.sentMessages.length + 1}`,
          conversationId,
          typeof payload.body === 'string' ? payload.body : '',
          userResponse(),
        )
        state.sentMessages.push(message)
        reply(socket, joinRef, ref, topic, {
          message,
          client_ref:
            typeof payload.client_ref === 'string' ? payload.client_ref : null,
        })
      }
    })
  })
}

function reply(
  socket: WebSocketRoute,
  joinRef: unknown,
  ref: unknown,
  topic: string,
  response: Record<string, unknown>,
): void {
  socket.send(
    JSON.stringify([
      joinRef,
      ref,
      topic,
      'phx_reply',
      { response, status: 'ok' },
    ]),
  )
}

function decodePhoenixFrame(
  rawMessage: string | Buffer,
): [unknown, unknown, string, string, unknown] | null {
  const frame: unknown = JSON.parse(String(rawMessage))
  if (
    !Array.isArray(frame) ||
    frame.length !== 5 ||
    typeof frame[2] !== 'string' ||
    typeof frame[3] !== 'string'
  ) {
    return null
  }

  return [frame[0], frame[1], frame[2], frame[3], frame[4]]
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return {}
  }

  return value as Record<string, unknown>
}

async function fulfillJson(
  route: Route,
  status: number,
  body: unknown,
): Promise<void> {
  await route.fulfill({
    status,
    contentType: 'application/json',
    body: JSON.stringify(body),
  })
}

async function fulfillEmpty(route: Route, status: number): Promise<void> {
  await route.fulfill({ status, body: '' })
}
