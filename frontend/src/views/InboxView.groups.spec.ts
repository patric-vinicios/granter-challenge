import { screen } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, it, expect, vi } from 'vitest'

import {
  authenticate,
  contactResponse,
  groupResponse,
  historyResponse,
  inboxSummaryResponse,
  jsonResponse,
  mockAuthenticatedFetch,
  renderInbox,
  resetInboxHarness,
} from './inbox/inboxTestHarness'

describe('Inbox groups', () => {
  beforeEach(resetInboxHarness)

  it('loads group members when opening details from an inbox summary', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [
        inboxSummaryResponse({
          id: 'group-product',
          type: 'group',
          title: 'Time de Produto',
          senderId: 'user-rafael',
          body: 'Mensagem do grupo',
          unreadCount: 0,
          memberCount: 3,
        }),
      ],
      conversationDetails: groupResponse(),
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(await screen.findByRole('button', { name: /time de produto/i }))
    await user.click(screen.getByRole('button', { name: /gerenciar grupo/i }))

    expect(await screen.findByText('@anabeatriz')).toBeTruthy()
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/group-product',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({ Authorization: 'Bearer jwt-token' }),
      }),
    )
  })

  it('keeps a group member visible and reports the API error when removal fails', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      conversations: [
        inboxSummaryResponse({
          id: 'group-product',
          type: 'group',
          title: 'Time de Produto',
          senderId: 'user-rafael',
          body: 'Mensagem do grupo',
          unreadCount: 0,
          memberCount: 3,
        }),
      ],
      conversationDetails: groupResponse(),
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(await screen.findByRole('button', { name: /time de produto/i }))
    await user.click(screen.getByRole('button', { name: /gerenciar grupo/i }))
    const removeAnaButton = await screen.findByRole('button', { name: /remover ana beatriz/i })

    fetchMock.mockResolvedValueOnce(
      jsonResponse(403, {
        errors: {
          code: 'forbidden',
          detail: 'Only the group creator can manage members',
        },
      }),
    )
    await user.click(removeAnaButton)

    expect((await screen.findByRole('alert')).textContent).toContain(
      'Apenas o criador do grupo pode gerenciar membros.',
    )
    expect(screen.getByRole('button', { name: /remover ana beatriz/i })).toBeTruthy()
  })

  it('validates the group name and contact selection before requesting creation', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({})
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /novo grupo/i }))
    await user.click(screen.getByRole('button', { name: /criar grupo/i }))

    expect(screen.getByRole('alert').textContent).toContain('Informe o nome do grupo.')
    expect(fetchMock).not.toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/groups',
      expect.objectContaining({ method: 'POST' }),
    )

    await user.type(screen.getByLabelText(/nome do grupo/i), 'Time sem membros')
    await user.click(screen.getByRole('button', { name: /criar grupo/i }))

    expect(screen.getByRole('alert').textContent).toContain('Selecione pelo menos um contato.')
    expect(fetchMock).not.toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/groups',
      expect.objectContaining({ method: 'POST' }),
    )
  })

  it('creates and manages a group from contacts', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      contacts: [
        contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
        contactResponse('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva'),
        contactResponse('contact-leticia', 'user-leticia', 'leticia', 'Leticia Moraes'),
      ],
    })
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

    fetchMock.mockResolvedValueOnce(jsonResponse(204, null))
    await user.click(screen.getByRole('button', { name: /sair do grupo/i }))

    expect(screen.queryByText('Time de Produto')).toBeNull()
  })
})
