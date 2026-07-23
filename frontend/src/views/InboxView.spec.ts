import { screen, within } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import { useAuthStore } from '@/stores/auth.store'
import { renderWithApp } from '@/test/render'

import InboxView from './InboxView.vue'

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

async function renderInbox() {
  return renderWithApp(InboxView, { routes, initialRoute: '/inbox' })
}

describe('InboxView', () => {
  it('shows the default conversation and switches to another conversation', async () => {
    const user = userEvent.setup()

    await renderInbox()

    expect(screen.getByText('visto por ultimo ha 5 min')).toBeTruthy()
    expect(screen.getByText('Perfeito, fico no aguardo entao')).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /time de produto/i }))

    expect(screen.getByText('5 membros · Voce, Rafael, Ana, +2')).toBeTruthy()
    expect(screen.getByText('Bom dia pessoal! Subi a build de staging pra validacao')).toBeTruthy()
    expect(screen.getAllByText('Rafael Alves')).toHaveLength(2)
  })

  it('opens contacts and reports add-contact success and error states', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        contacts: [
          contactResponse('contact-rafael', 'user-rafael', 'rafaelalves', 'Rafael Alves'),
          contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
        ],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))

    expect(screen.getByText('Contatos')).toBeTruthy()
    expect(await screen.findByText('@rafaelalves')).toBeTruthy()
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )

    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const dialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    const usernameInput = within(dialog).getByLabelText(/usuario/i)

    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, {
        contact: contactResponse('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva'),
      }),
    )

    await user.type(usernameInput, '@anabeatriz')
    await user.click(within(dialog).getByRole('button', { name: /adicionar/i }))

    expect(await within(dialog).findByText(/contato adicionado/i)).toBeTruthy()
    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ username: '@anabeatriz' }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
          'Content-Type': 'application/json',
        }),
      }),
    )
    expect(screen.getByText('@carlos')).toBeTruthy()

    await user.click(within(dialog).getByRole('button', { name: /voltar/i }))
    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const reopenedDialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    fetchMock.mockResolvedValueOnce(
      jsonResponse(404, {
        errors: {
          code: 'user_not_found',
          detail: 'No user with @fulano123 exists in the system',
        },
      }),
    )

    await user.type(within(reopenedDialog).getByLabelText(/usuario/i), '@fulano123')
    await user.click(within(reopenedDialog).getByRole('button', { name: /adicionar/i }))

    expect(await within(reopenedDialog).findByText(/usuario nao encontrado/i)).toBeTruthy()

    fetchMock.mockResolvedValueOnce(jsonResponse(204, null))
    await user.click(screen.getByRole('button', { name: /remover rafael alves/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/contacts/contact-rafael',
      expect.objectContaining({
        method: 'DELETE',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(screen.queryByText('@rafaelalves')).toBeNull()
  })

  it('opens a private conversation from a contact', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        contacts: [contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz')],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await screen.findByText('@anabeatriz')

    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, {
        conversation: privateConversationResponse('conversation-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
      }),
    )
    fetchMock.mockResolvedValueOnce(historyResponse())

    await user.click(screen.getByRole('button', { name: /abrir conversa com ana beatriz/i }))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/private',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ user_id: 'user-ana' }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/conversation-ana/messages?limit=30',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(await screen.findByText('Conversa iniciada')).toBeTruthy()
    expect(screen.getByText('Nenhuma mensagem nesta conversa.')).toBeTruthy()
  })

  it('loads and paginates persisted history for a backend conversation', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        contacts: [contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz')],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await screen.findByText('@anabeatriz')

    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, {
        conversation: privateConversationResponse('conversation-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
      }),
    )
    fetchMock.mockResolvedValueOnce(
      historyResponse({
        messages: [
          messageResponse('message-2', 'Mensagem mais recente', 'user-current', 'Patric', '2026-07-22T13:49:00Z'),
        ],
        nextCursor: 'older-cursor',
        hasMore: true,
      }),
    )

    await user.click(screen.getByRole('button', { name: /abrir conversa com ana beatriz/i }))

    expect(await screen.findByText('Mensagem mais recente')).toBeTruthy()

    fetchMock.mockResolvedValueOnce(
      historyResponse({
        messages: [messageResponse('message-1', 'Mensagem anterior', 'user-ana', 'Ana Beatriz', '2026-07-22T13:40:00Z')],
        nextCursor: null,
        hasMore: false,
      }),
    )

    await user.click(screen.getByRole('button', { name: /carregar mensagens anteriores/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/conversation-ana/messages?limit=30&before=older-cursor',
      expect.objectContaining({ method: 'GET' }),
    )
    expect(await screen.findByText('Mensagem anterior')).toBeTruthy()
    expect(screen.queryByRole('button', { name: /carregar mensagens anteriores/i })).toBeNull()
  })

  it('shows a history load error for a backend conversation', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        contacts: [contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz')],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await screen.findByText('@anabeatriz')

    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, {
        conversation: privateConversationResponse('conversation-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
      }),
    )
    fetchMock.mockResolvedValueOnce(
      jsonResponse(400, {
        errors: {
          code: 'invalid_cursor',
          detail: 'The pagination cursor is invalid',
        },
      }),
    )

    await user.click(screen.getByRole('button', { name: /abrir conversa com ana beatriz/i }))

    expect(await screen.findByText('O cursor de paginação é inválido.')).toBeTruthy()
  })

  it('opens conversation search and clears the draft when sending', async () => {
    const user = userEvent.setup()

    await renderInbox()

    await user.click(screen.getByRole('button', { name: /buscar na conversa/i }))

    expect(screen.getByLabelText(/buscar na conversa/i)).toBeTruthy()
    expect(screen.getByText('1 / 1')).toBeTruthy()

    const messageInput = screen.getByLabelText(/^mensagem$/i) as HTMLTextAreaElement

    await user.type(messageInput, 'Mensagem de teste')
    await user.click(screen.getByRole('button', { name: /enviar mensagem/i }))

    expect(messageInput.value).toBe('')
  })

  it('creates and manages a group from contacts', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        contacts: [
          contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
          contactResponse('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva'),
          contactResponse('contact-leticia', 'user-leticia', 'leticia', 'Leticia Moraes'),
        ],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /novo grupo/i }))
    await user.click(screen.getByLabelText(/ana beatriz/i))
    await user.click(screen.getByLabelText(/carlos silva/i))

    fetchMock.mockResolvedValueOnce(jsonResponse(201, { conversation: groupResponse() }))
    fetchMock.mockResolvedValueOnce(historyResponse())

    await user.clear(screen.getByLabelText(/nome do grupo/i))
    await user.type(screen.getByLabelText(/nome do grupo/i), 'Time de Produto')
    await user.click(screen.getByRole('button', { name: /criar grupo/i }))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/groups',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ name: 'Time de Produto', member_ids: ['user-ana', 'user-carlos'] }),
      }),
    )
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/group-product/messages?limit=30',
      expect.objectContaining({ method: 'GET' }),
    )
    expect(await screen.findByText('Grupo criado')).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /gerenciar grupo/i }))
    expect(screen.getByText('@anabeatriz')).toBeTruthy()

    fetchMock.mockResolvedValueOnce(jsonResponse(204, null))
    await user.click(screen.getByRole('button', { name: /remover ana beatriz/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/group-product/members/user-ana',
      expect.objectContaining({ method: 'DELETE' }),
    )
    expect(screen.queryByRole('button', { name: /remover ana beatriz/i })).toBeNull()

    fetchMock.mockResolvedValueOnce(jsonResponse(200, { conversation: groupResponse({ includeAna: false, includeLeticia: true }) }))
    await user.click(screen.getByRole('button', { name: /leticia moraes/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/conversations/group-product/members',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ member_ids: ['user-leticia'] }),
      }),
    )
    expect(await screen.findByText('@leticia')).toBeTruthy()
  })
})

function authenticate(pinia: Awaited<ReturnType<typeof renderInbox>>['pinia']) {
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

function contactResponse(id: string, userId: string, username: string, name: string) {
  return {
    id,
    user: {
      id: userId,
      username,
      name,
      last_seen_at: null,
    },
  }
}

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

function groupResponse(options: { includeAna?: boolean; includeLeticia?: boolean } = {}) {
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
  }
}

function historyResponse(
  options: {
    messages?: ReturnType<typeof messageResponse>[]
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

function messageResponse(id: string, body: string, senderId: string, senderName: string, insertedAt: string) {
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
    },
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
